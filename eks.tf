data "aws_caller_identity" "current" {}

locals {
  eks_cluster = {
    min_size                 = 3
    max_size                 = 4
    desired_size             = 3
    name                     = "eks-self-managed-ayush-1"
    version                  = "1.24"
    is_mixed_instance_policy = true
    instance_type            = "t3a.medium"
    instances_distribution = {
      on_demand_base_capacity  = 0
      on_demand_percentage_above_base_capacity     = 20
      spot_allocation_strategy = "capacity-optimized"
    }
    override = [
      {
        instance_type     = "t3a.large"
        weighted_capacity = "1"
      },
      {
        instance_type     = "t3.large"
        weighted_capacity = "2"
      },
    ]
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 50
          volume_type           = "gp3"
          iops                  = 3000
          throughput            = 150
          encrypted             = true
          delete_on_termination = true
        }
      }
    }
    cluster_security_group = {
      cluster_rule_ingress = {
        description                = "cluster SG"
        protocol                   = "tcp"
        from_port                  = 0
        to_port                    = 65535
        type                       = "ingress"
        cidr_blocks = ["0.0.0.0/0"]
      },
      cluster_rule_egress = {
        description                = "cluster SG"
        protocol                   = "tcp"
        from_port                  = 0
        to_port                    = 65535
        type                       = "egress"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    node_security_group = {
      node_rules_ingress = {
        description = "node SG"
        protocol    = "TCP"
        from_port   = 0
        to_port     = 65535
        type        = "ingress"
        cidr_blocks = ["0.0.0.0/0"]
      }
      node_rules_egress = {
        description                   = "node SG"
        protocol                      = "tcp"
        from_port                     = 0
        to_port                       = 65535
        type                          = "egress"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    #aws eks describe-addon-version
    addons = {
      vpc-cni = {
        resolve_conflicts = "OVERWRITE"
      },
      # aws-ebs-csi-driver = {
      #   resolve_conflicts = "OVERWRITE"
      # },
      kube-proxy= {
        resolve_conflicts = "OVERWRITE"
      }
    }
    lb = {
      image = {
        repository= "public.ecr.aws/eks/aws-load-balancer-controller"
        tag= "v2.4.6"
      }
    }
  }
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", local.eks_cluster.name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", local.eks_cluster.name]
    }
  }
}

# provider "kubectl" {
#   kubernetes {
#     host                   = module.eks_cluster.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "aws"
#       args = ["eks", "get-token", "--cluster-name", local.eks_cluster.name]
#     }
#   }
# }

module "eks_cluster" {
  source = "git::https://github.com/tothenew/terraform-aws-eks.git"
  #source = "../"
  cluster_name    = local.eks_cluster.name
  cluster_version = try(local.eks_cluster.version, "1.24")

  cluster_endpoint_private_access = try(local.eks_cluster.cluster_endpoint_private_access, false)
  cluster_endpoint_public_access  = try(local.eks_cluster.cluster_endpoint_public_access, true)

  vpc_id     = "vpc-0cdbbbd4cedcea769"
  subnet_ids = ["subnet-0257e8262a7017948", "subnet-062a9cb5ea10455da", "subnet-06b6a7e3c22de35ca"]

  # Self managed node groups will not automatically create the aws-auth configmap so we need to
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  create                    = true

  #Cluster Level Addons
  # cluster_addons = local.eks_cluster.addons

  self_managed_node_group_defaults = {
    instance_type                          = "${local.eks_cluster.instance_type}"
    update_launch_template_default_version = true
    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]
  }

  # cluster_security_group_additional_rules = local.eks_cluster.cluster_security_group

  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    # default_node_group = {
    #   name = local.eks_cluster.name
    # }
    mixed = {
      name = local.eks_cluster.name
      min_size     = try(local.eks_cluster.min_size, 2)
      max_size     = try(local.eks_cluster.max_size, 4)
      desired_size = try(local.eks_cluster.min_size, 2)
      tags = {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.eks_cluster.name}" = "owned"
      }
      create_security_group          = true
      security_group_name            = local.eks_cluster.name
      security_group_use_name_prefix = true
      security_group_description     = "Self managed NodeGroup SG"
      security_group_rules = local.eks_cluster.node_security_group

      # pre_bootstrap_user_data = <<-EOT
      #   TOKEN=`curl -s  -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
      #   EC2_LIFE_CYCLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-life-cycle)
      #   INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-type)
      #   AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/placement/availability-zone)
      #   EOT

      # bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle='\"$EC2_LIFE_CYCLE\"' --register-with-taints=instance_type='\"$INSTANCE_TYPE\"':NoSchedule,ec2_lifecycle='\"$EC2_LIFE_CYCLE\"':NoSchedule,availability_zone='\"$AVAILABILITY_ZONE\"':NoSchedule'"


      post_bootstrap_user_data = <<-EOT
        cd /tmp
        sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
        sudo systemctl enable amazon-ssm-agent
        sudo systemctl start amazon-ssm-agent
        EOT

      block_device_mappings = "${local.eks_cluster.block_device_mappings}"
      use_mixed_instances_policy = "${local.eks_cluster.is_mixed_instance_policy}"
      mixed_instances_policy = {
        instances_distribution = "${local.eks_cluster.instances_distribution}"
        override = "${local.eks_cluster.override}"
      }
    }
  }
}

module "load_balancer_controller" {
  source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/terraform-aws-eks-lb-controller"

  cluster_identity_oidc_issuer     = module.eks_cluster.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks_cluster.oidc_provider_arn
  cluster_name                     = module.eks_cluster.cluster_id
  depends_on = [
    module.eks_cluster
  ]
  settings = local.eks_cluster.lb
}

# resource "kubernetes_ingress_v1" "example_ingress" {
#   depends_on = [
#     module.load_balancer_controller
#   ]
#   metadata {
#     name = "example-ingress"
#     annotations = {
#       "kubernetes.io/ingress.class"                  = "alb"
#       "alb.ingress.kubernetes.io/target-type"        = "ip"
#       "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
#       "alb.ingress.kubernetes.io/load-balancer-name" = "${local.eks_cluster.name}-alb"
#       "alb.ingress.kubernetes.io/healthcheck-path"   = "/health"
#       "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\": 80}]"
#       "alb.ingress.kubernetes.io/group.name"         = "eks-prod-alb"
#       "alb.ingress.kubernetes.io/subnets"            = "subnet-0257e8262a7017948,subnet-062a9cb5ea10455da,subnet-06b6a7e3c22de35ca"
#     }
#   }

#   spec {
#       rule {
#         http {
#          path {
#            path = "/app-1*"
#            backend {
#              service {
#                name = "myapp-1"
#                port {
#                  number = 80
#                }
#              }
#            }
#         }
#       }
#     }
#   }
# }

# resource "kubernetes_service_v1" "example" {
#   depends_on = [
#     module.load_balancer_controller
#   ]
#   metadata {
#     name = "myapp-1"
#   }
#   spec {
#     selector = {
#       app = kubernetes_pod.example.metadata.0.labels.app
#     }
#     session_affinity = "ClientIP"
#     port {
#       port        = 80
#       target_port = 80
#     }

#     type = "NodePort"
#   }
# }


# resource "kubernetes_pod" "example" {
#   depends_on = [
#     module.load_balancer_controller
#   ]
#   metadata {
#     name = "terraform-example"
#     labels = {
#       app = "myapp-1"
#     }
#   }

#   spec {
#     container {
#       image = "nginx:latest"
#       name  = "example"

#       port {
#         container_port = 80
#       }
#     }
#   }
# }

resource "helm_release" "ingress" {
  name       = "helm-ing"
  namespace   = "default"
#  repository = "https://charts.bitnami.com/bitnami"
  chart      = "./helm/alb-ingress"
  version    = "6.0.1"

  values = [
    "${file("./helm/alb-ingress/values.yaml")}"
  ]
}

resource "kubernetes_config_map" "kong-config" {
  metadata {
    name = "kong-config"
  } 
  depends_on = [
    module.create_database
  ]

  data = {
    "nginx_kong.lua" = "${file("./helm/configmap.yml")}"
  }
}

resource "helm_release" "kong1" {
  depends_on = [
    resource.kubernetes_pod.kong_migration
  ]
  name       = "kong1"
  timeout = 60
  # namespace   = "default"
#  repository = "https://charts.bitnami.com/bitnami"
  chart      = "./helm/kong"
  # version    = "6.0.1"
  # set {
  #   name  = "config"
  #   value = file("./helm/configmap.conf")
  # }
  values = [
    "${file("./helm/kong-values.yaml")}"
  ]
}

resource "helm_release" "konga1" {
  depends_on = [
    helm_release.kong1
  ]
  name       = "konga1"
  # namespace   = "default"
#  repository = "https://charts.bitnami.com/bitnami"
  chart      = "./helm/konga"
  # version    = "6.0.1"
  timeout = 120
  values = [
    "${file("./helm/konga-values.yaml")}"
  ]
}

# psql -h kong-database-0.c8m4uwvxecdh.ap-south-1.rds.amazonaws.com -U root postgres 
# b9909FTArBOsPoOlYERWC8QMex9KrIEXll

# k run kong --image=saifahmadttn/kong:2.7.0 --env=KONG_PG_USER=root --env=KONG_PG_DATABASE=kong_db --env=KONG_DATABASE=postgres --env=KONG_PG_PASSWORD=b9909FTArBOsPoOlYERWC8QMex9KrIEXll --env=KONG_PG_HOST=kong-database-0.c8m4uwvxecdh.ap-south-1.rds.amazonaws.com --command -- kong migrations bootstrap

module "create_database" {
  source              = "git::https://github.com/ayushme001/terraform-aws-rds.git"
  create_rds     = false
  create_aurora = true

  subnet_ids       = ["subnet-0257e8262a7017948","subnet-062a9cb5ea10455da"]
  vpc_id           = "vpc-0cdbbbd4cedcea769"
  vpc_cidr         = ["172.31.0.0/16"]

  publicly_accessible = true
  allocated_storage = 10
  max_allocated_storage = 20
  engine = "aurora-postgresql"
  engine_version = "11.18"
  instance_class = "db.t3.medium"
  database_name = "mydb"
  username   = "root"
  identifier = "kong-database"
  apply_immediately = false
  storage_encrypted = false
  multi_az = false
  db_subnet_group_id = "kong-rds"
  deletion_protection = false
  auto_minor_version_upgrade = false
  count_aurora_instances = 1
  serverlessv2_scaling_configuration_max = 1.0
  serverlessv2_scaling_configuration_min = 0.5
  common_tags = {
    "Project"     = "Kong",
    "Environment" = "dev"
  }
  environment = "dev"
}


data "aws_ssm_parameter" "rds_host" {
  depends_on = [
    module.create_database
  ]
  name = "/dev/RDS/HOST"
}

data "aws_ssm_parameter" "rds_password" {
  depends_on = [
    module.create_database
  ]
  name = "/dev/RDS/PASSWORD"
}

data "aws_ssm_parameter" "rds_user" {
  depends_on = [
    module.create_database
  ]
  name = "/dev/RDS/USER"
}

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    postgresql = { # This line is what needs to change.
      source = "cyrilgdn/postgresql"
      version = "1.15.0"
    }
  }
}

provider "postgresql" {
  host            = "kong-database.cluster-c8m4uwvxecdh.ap-south-1.rds.amazonaws.com"
  port            = 5432
  database        = "postgres"
  username        = "root"
  password        = "vT3JUoJmPqUVBPuWZ4NtCiFnCH6JSyXPz4"
  connect_timeout = 15
}

resource "postgresql_database" "kong" {
  depends_on = [
    module.create_database
  ]
  name     = "kong_db"
}

resource "postgresql_database" "konga" {
  depends_on = [
    module.create_database
  ]
  name     = "konga_db"
}

resource "kubernetes_pod" "kong_migration" {
  depends_on = [
    kubernetes_config_map.kong-config
  ]
  metadata {
    name = "kong-migration"
  }

  spec {
    container {
      image = "saifahmadttn/kong:2.7.0"
      name  = "kong-migration"

      env {
        name  = "KONG_DATABASE"
        value = "postgres"
      }
      env {
        name  = "KONG_PG_HOST"
        value = "kong-database.cluster-c8m4uwvxecdh.ap-south-1.rds.amazonaws.com"
      }
      env {
        name  = "KONG_PG_USER"
        value = "root"
      }
      env {
        name  = "KONG_PG_PASSWORD"
        value = "vT3JUoJmPqUVBPuWZ4NtCiFnCH6JSyXPz4"
      }
      env {
        name  = "KONG_ADMIN_LISTEN"
        value = "0.0.0.0:8001"
      }
      env {
        name  = "KONG_ADMIN_LISTEN_SSL"
        value = "0.0.0.0:8444"
      }
      env {
        name  = "KONG_TRUSTED_IPS"
        value = "0.0.0.0/0,::/0"
      }
      env {
        name  = "KONG_PG_DATABASE"
        value = "kong_db"
      }
      command = [ "kong", "migrations", "bootstrap" ]
      port {
        container_port = 8001
      }
    }
    # dns_policy = "None"
  }
}

module "helm_iam_policy" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-policy"

  name        = "${local.workspace.eks_cluster.name}-shared-apps-helm-integration-policy"
  path        = "/"
  description = "Policy for EKS load-balancer-controller"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetSecretValue",
                "ssm:DescribeParameters",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "kms:DescribeCustomKeyStores",
                "kms:ListKeys",
                "kms:ListAliases"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "kms:Decrypt",
                "kms:GetKeyRotationStatus",
                "kms:GetKeyPolicy",
                "kms:DescribeKey"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
    
EOF
}



module "secrets-store-csi" {
  depends_on = [
    module.eks_cluster
  ]
  source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/secret-store-csi"
  cluster_name = module.eks_cluster.cluster_id
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  chart_version = local.workspace.eks_cluster.secrets-store-csi.chart_version
  ascp_chart_version = local.workspace.eks_cluster.secrets-store-csi.ascp_chart_version
  syncSecretEnabled = local.workspace.eks_cluster.secrets-store-csi.syncSecretEnabled
  enableSecretRotation = local.workspace.eks_cluster.secrets-store-csi.enableSecretRotation
  namespace_service_accounts = ["${local.workspace.environment_name}:kong-service-role","${local.workspace.environment_name}:konga-service-role"]
}
resource "aws_iam_role_policy_attachment" "secrets_integration_policy_attachment" {
  depends_on = [
    module.secrets-store-csi
  ]
  count = 1
  role       = module.secrets-store-csi.iam_role_name
  policy_arn = module.helm_iam_policy.arn
}
