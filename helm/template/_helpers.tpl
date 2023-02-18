{{/*
Default Template for Service Account. All Sub-Charts under this Chart can include the below template.
*/}}
{{- define "apps.serviceaccounttemplate" }}
apiVersion: v1
kind: ServiceAccount
metadata:
    name: "{{ .Values.name }}-service-role"
    namespace: "{{ $.Release.Namespace }}"
    annotations:
      eks.amazonaws.com/role-arn: {{ $.Values.global.roleArn }}

{{- end }}

{{/*
Default Template for Secret Provider Class. All Sub-Charts under this Chart can include the below template.
*/}}
{{- define "apps.spctemplate" }}
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets2
  namespace: {{ $.Release.Namespace }}
spec:
  provider: aws
  secretObjects:
    - secretName: vr-creds
      type: Opaque
      data:
        - objectName: rds-endpoint
          key: DATABASE_HOST_STRING_Secret
        - objectName: rds-password
          key: DB_PASSWORD_Secret
        - objectName: rds-user
          key: DB_USER_NAME_Secret
        - objectName: rds-name
          key: DATABASE_NAME_Secret
        
  parameters:
    objects: |
        - objectName: "/{{ $.Release.Namespace }}/RDS/ENDPOINT"
          objectType: "ssmparameter"
          objectAlias: rds-endpoint
        - objectName: "/{{ $.Release.Namespace }}/RDS/PASSWORD"
          objectType: "ssmparameter"
          objectAlias: rds-password
        - objectName: "/{{ $.Release.Namespace }}/RDS/USER"
          objectType: "ssmparameter"
          objectAlias: rds-user
        - objectName: "/{{ $.Release.Namespace }}/RDS/NAME"
          objectType: "ssmparameter"
          objectAlias: rds-name
{{- end }}

{{/*
Default Template for Secret-Provider-Class-Volume. All Sub-Charts under this Chart can include the below template.
*/}}
{{- define "apps.spcvolume" }}
volumes:
- name: application-logs
  hostPath:
    path: /opt/logs/{{ .Values.appName }}
- name: creds-volume
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
        secretProviderClass: aws-secrets2
{{- end }}
