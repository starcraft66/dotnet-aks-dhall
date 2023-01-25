let Prelude =
    -- Latest version of the Prelude at the time of creating this
      https://prelude.dhall-lang.org/v21.1.0/package.dhall
        sha256:0fed19a88330e9a8a3fbe1e8442aa11d12e38da51eb12ba8bcb56f3c25d0854a

let kubernetes =
    -- Targetting kubernetes 1.23
      https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/1.23/package.dhall
        sha256:bc1e882fb24b98974d9c2210d2987ecbf661290f5c74b2dd6fa82562a5b41c5d

let dotnetMonitorVersion =
    -- Container image tag for dotnet-monitor sidecar
      "6.1.1"

let SecretProviderClassSecretObjectData =
      { Type = { key : Text, objectName : Text }, default = {=} }

let SecretProviderClassSecretObjects =
      { Type =
          { data : List SecretProviderClassSecretObjectData.Type
          , secretName : Text
          , type : Text
          }
      , default =
        { data = [] : List SecretProviderClassSecretObjectData.Type
        , secretName = None Text
        , type = None Text
        }
      }

let SecretProviderClassParameters =
      { Type =
          { usePodIdentity : Optional Text
          , useVMManagedIdentity : Optional Text
          , userAssignedIdentityID : Optional Text
          , keyvaultName : Text
          , tenantId : Text
          , objects : Text
          }
      , default =
        { usePodIdentity = Some "false"
        , useVMManagedIdentity = Some "false"
        , userAssignedIdentityID = None Text
        , keyvaultName = None Text
        , tenantId = "5dda54da-ba38-4375-88f8-6420cab22451"
        , objects = None Text
        }
      }

let SecretProviderClassSpec =
      { Type =
          { provider : Optional Text
          , secretObjects :
              Optional (List SecretProviderClassSecretObjects.Type)
          , parameters : Optional SecretProviderClassParameters.Type
          }
      , default =
        { provider = None Text
        , secretObjects = None (List SecretProviderClassSecretObjects.Type)
        , parameters = None SecretProviderClassParameters.Type
        }
      }

let SecretProviderClass =
      { Type =
          { apiVersion : Text
          , kind : Text
          , metadata : kubernetes.ObjectMeta.Type
          , spec : SecretProviderClassSpec.Type
          }
      , default =
        { apiVersion = "secrets-store.csi.x-k8s.io/v1"
        , kind = "SecretProviderClass"
        }
      }

let KubernetesManifest =
    -- Our own union for kubernetes manifests because the union from dhall-kubernetes cannot be extended to add CRDs (SecretProviderClass in this case)
      < Deployment : kubernetes.Deployment.Type
      | SecretProviderClass : SecretProviderClass.Type
      | ConfigMap : kubernetes.ConfigMap.Type
      | Service : kubernetes.Service.Type
      | Ingress : kubernetes.Ingress.Type
      >

let ConfigElement = { Type = { key : Text, value : Text }, default = {=} }

let AppConfiguration =
      { Type = { name : Text, elements : List ConfigElement.Type }
      , default = {=}
      }

let KeyVaultSecrets =
      { Type = { keyVaultName : Text, secrets : List ConfigElement.Type }
      , default = {=}
      }

let WebConfiguration =
      { Type = { enabled : Bool, tls : Bool, hosts : List Text }
      , default = { enabled = False, tls = False, hosts = [] : List Text }
      }

let Image =
      { Type = { registry : Text, name : Text, tag : Text }
      , default.tag = "latest"
      }

let DotNetApplication =
    -- Dotnet function app Type
      { Type =
          { name : Text
          , image : Image.Type
          , replicas : Natural
          , nodePool : Text
          , config : List ConfigElement.Type
          , keyVaultSecrets : List KeyVaultSecrets.Type
          , webConfiguration : WebConfiguration.Type
          }
      , default =
        { replicas = 1
        , nodePool = "default"
        , webConfiguration = WebConfiguration::{=}
        }
      }

let makeImageString
    : Image.Type -> Text
    =
      -- Make container  image string from Image type
      \(image : Image.Type) ->
        image.registry ++ "/" ++ image.name ++ ":" ++ image.tag

let makeSecretObjects
    : KeyVaultSecrets.Type -> SecretProviderClassSecretObjects.Type
    = -- Make SecretProviderClass secret objects
      \(kv : KeyVaultSecrets.Type) ->
        let makeSecretObjectData
            : ConfigElement.Type -> SecretProviderClassSecretObjectData.Type
            = -- Make SecretProviderClass secret object data
              \(ce : ConfigElement.Type) ->
                SecretProviderClassSecretObjectData::{
                , key = ce.key
                , objectName = ce.value
                }

        in  SecretProviderClassSecretObjects::{
            , data =
                Prelude.List.map
                  ConfigElement.Type
                  SecretProviderClassSecretObjectData.Type
                  makeSecretObjectData
                  kv.secrets
            , secretName = "azure-key-vault-" ++ kv.keyVaultName
            , type = "Opaque"
            }

let makeInlineYamlObjects
    : KeyVaultSecrets.Type -> Text
    = -- Make list of inline YAML objects for SecretProviderClass data
      \(kv : KeyVaultSecrets.Type) ->
        let makeInlineYamlObject
            : ConfigElement.Type -> Text
            = -- Make single YAML object for SecretProviderClass data
              \(elem : ConfigElement.Type) ->
                ''
                  - |
                    objectName: "${elem.value}"
                    objectAlias: "${elem.key}"
                    objectType: "secret"
                    objectVersion: ""
                ''

        in      ''
                array:
                ''
            ++  Prelude.Text.concatSep
                  ""
                  ( Prelude.List.map
                      ConfigElement.Type
                      Text
                      makeInlineYamlObject
                      kv.secrets
                  )

let makeAzureKeyVaultSecretProviderClasses
    : DotNetApplication.Type -> List KubernetesManifest
    = -- Make Azure Key Vault SecretProviderClass CR for each Key Vault
      \(app : DotNetApplication.Type) ->
        let makeAzureKeyVaultSecretProviderClass
            : KeyVaultSecrets.Type -> KubernetesManifest
            = -- Make Azure Key Vault SecretProviderClass CR for single key vault
              \(kv : KeyVaultSecrets.Type) ->
                KubernetesManifest.SecretProviderClass
                  SecretProviderClass::{
                  , metadata = kubernetes.ObjectMeta::{
                    , name = Some ("azure-key-vault-" ++ kv.keyVaultName)
                    }
                  , spec = SecretProviderClassSpec::{
                    , provider = Some "azure"
                    , secretObjects = Some [ makeSecretObjects kv ]
                    , parameters = Some SecretProviderClassParameters::{
                      , usePodIdentity = Some "false"
                      , useVMManagedIdentity = Some "false"
                      , userAssignedIdentityID = Some ""
                      , keyvaultName = kv.keyVaultName
                      , objects = makeInlineYamlObjects kv
                      }
                    }
                  }

        in  Prelude.List.map
              KeyVaultSecrets.Type
              KubernetesManifest
              makeAzureKeyVaultSecretProviderClass
              app.keyVaultSecrets

let makeSecretEnvSourcesFromKeyVaults
    : List KeyVaultSecrets.Type -> List kubernetes.EnvFromSource.Type
    = -- Make list of EnvFrom sources referring to secrets populated by the Key Vault CSI driver
      \(kvs : List KeyVaultSecrets.Type) ->
        let makeSecretEnvSourcesFromKeyVault
            : KeyVaultSecrets.Type -> kubernetes.EnvFromSource.Type
            = -- Make single EnvFrom source referring to secrets populated by the Key Vault CSI driver
              \(kv : KeyVaultSecrets.Type) ->
                kubernetes.EnvFromSource::{
                , secretRef = Some kubernetes.SecretEnvSource::{
                  , name = Some ("azure-key-vault-" ++ kv.keyVaultName)
                  }
                }

        in  Prelude.List.map
              KeyVaultSecrets.Type
              kubernetes.EnvFromSource.Type
              makeSecretEnvSourcesFromKeyVault
              kvs

let makeVolumesForKeyVaults
    : List KeyVaultSecrets.Type -> List kubernetes.Volume.Type
    = -- Make list of pod volume definitions for Key Vault CSI driver attachments
      \(kvs : List KeyVaultSecrets.Type) ->
        let makeVolumeForKeyVault
            : KeyVaultSecrets.Type -> kubernetes.Volume.Type
            = -- Make single pod volume definition for Key Vault CSI driver attachments
              \(kv : KeyVaultSecrets.Type) ->
                kubernetes.Volume::{
                , name = "azure-key-vault-" ++ kv.keyVaultName
                , csi = Some kubernetes.CSIVolumeSource::{
                  , driver = "secrets-store.csi.k8s.io"
                  , readOnly = Some True
                  , volumeAttributes = Some
                      ( toMap
                          { secretProviderClass =
                              "azure-key-vault-" ++ kv.keyVaultName
                          }
                      )
                  }
                }

        in  Prelude.List.map
              KeyVaultSecrets.Type
              kubernetes.Volume.Type
              makeVolumeForKeyVault
              kvs

let makeVolumeMountsForKeyVaults
    : List KeyVaultSecrets.Type -> List kubernetes.VolumeMount.Type
    = -- Make list of container volume mounts for key vault volumes
      \(kvs : List KeyVaultSecrets.Type) ->
        let makeVolumeMountForKeyVault
            : KeyVaultSecrets.Type -> kubernetes.VolumeMount.Type
            = -- Make container volume mount for key vault volume
              \(kv : KeyVaultSecrets.Type) ->
                kubernetes.VolumeMount::{
                , name = "azure-key-vault-" ++ kv.keyVaultName
                , mountPath = "/mnt/" ++ "azure-key-vault-" ++ kv.keyVaultName
                , readOnly = Some True
                }

        in  Prelude.List.map
              KeyVaultSecrets.Type
              kubernetes.VolumeMount.Type
              makeVolumeMountForKeyVault
              kvs

let makeConfigMap
    : DotNetApplication.Type -> kubernetes.ConfigMap.Type
    = -- Make whole ConfigMap from ConfigElement Types
      \(app : DotNetApplication.Type) ->
        let configElementToMap
            : ConfigElement.Type -> { mapKey : Text, mapValue : Text }
            = -- Make configmap entry (map) from ConfigElement Type
              \(element : ConfigElement.Type) ->
                { mapKey = element.key, mapValue = element.value }

        in  kubernetes.ConfigMap::{
            , metadata = kubernetes.ObjectMeta::{
              , name = Some (app.name ++ "-config")
              }
            , data = Some
                ( Prelude.List.map
                    ConfigElement.Type
                    { mapKey : Text, mapValue : Text }
                    configElementToMap
                    app.config
                )
            }

let makeWebService
    : DotNetApplication.Type -> kubernetes.Service.Type
    = -- Make Service exposing HTTP port 80 of application
      \(app : DotNetApplication.Type) ->
        kubernetes.Service::{
        , metadata = kubernetes.ObjectMeta::{ name = Some app.name }
        , spec = Some kubernetes.ServiceSpec::{
          , ports = Some
            [ kubernetes.ServicePort::{
              , name = Some "http"
              , protocol = Some "TCP"
              , port = 80
              , targetPort = Some (kubernetes.NatOrString.String "http")
              }
            ]
          , selector = Some (toMap { `app.kubernetes.io/name` = app.name })
          }
        }

let makeWebIngress
    : DotNetApplication.Type -> kubernetes.Ingress.Type
    = -- Make ingress for application with ingressrules and TLS config for each domain
      \(app : DotNetApplication.Type) ->
        let makeIngressRules
            : DotNetApplication.Type -> List kubernetes.IngressRule.Type
            = -- Make list of ingress rules for ingress
              \(app : DotNetApplication.Type) ->
                let makeIngressRulePath
                    : Text -> kubernetes.IngressRule.Type
                    = -- Make ingress rule with "/" prefix path to http service
                      \(host : Text) ->
                        kubernetes.IngressRule::{
                        , host = Some host
                        , http = Some
                          { paths =
                            [ kubernetes.HTTPIngressPath::{
                              , backend = kubernetes.IngressBackend::{
                                , service = Some kubernetes.IngressServiceBackend::{
                                  , name = app.name
                                  , port = Some kubernetes.ServiceBackendPort::{
                                    , name = Some "http"
                                    }
                                  }
                                }
                              , pathType = "Prefix"
                              }
                            ]
                          }
                        }

                in  Prelude.List.map
                      Text
                      kubernetes.IngressRule.Type
                      makeIngressRulePath
                      app.webConfiguration.hosts

        let makeIngressTLS
            : DotNetApplication.Type -> kubernetes.IngressTLS.Type
            = -- Make ingress TLS certificate configuration for each domain
              \(app : DotNetApplication.Type) ->
                { hosts = Some app.webConfiguration.hosts
                , secretName = Some "${app.name}-tls-certificate"
                }

        in  kubernetes.Ingress::{
            , metadata = kubernetes.ObjectMeta::{
              , name = Some app.name
              , annotations = Some
                  ( toMap
                      { `cert-manager.io/cluster-issuer` = "letsencrypt-prod" }
                  )
              }
            , spec = Some kubernetes.IngressSpec::{
              , ingressClassName = Some "nginx"
              , rules = Some (makeIngressRules app)
              , tls =
                  if    app.webConfiguration.tls
                  then  Some [ makeIngressTLS app ]
                  else  None (List kubernetes.IngressTLS.Type)
              }
            }

let makeDeployment
    : DotNetApplication.Type -> kubernetes.Deployment.Type
    = -- Make deployment for dotnet application with all settings
      \(app : DotNetApplication.Type) ->
        kubernetes.Deployment::{
        , metadata = kubernetes.ObjectMeta::{ name = Some app.name }
        , spec = Some kubernetes.DeploymentSpec::{
          , selector = kubernetes.LabelSelector::{
            , matchLabels = Some (toMap { `app.kubernetes.io/name` = app.name })
            }
          , replicas = Some app.replicas
          , template = kubernetes.PodTemplateSpec::{
            , metadata = Some kubernetes.ObjectMeta::{
              , labels = Some (toMap { `app.kubernetes.io/name` = app.name })
              }
            , spec = Some kubernetes.PodSpec::{
              , containers =
                [ kubernetes.Container::{
                  , name = app.name
                  , envFrom = Some
                      (   makeSecretEnvSourcesFromKeyVaults app.keyVaultSecrets
                        # [ kubernetes.EnvFromSource::{
                            , configMapRef = Some kubernetes.ConfigMapEnvSource::{
                              , name = Some (app.name ++ "-config")
                              }
                            }
                          ]
                      )
                  , image = Some (makeImageString app.image)
                  , ports = Some
                    [ kubernetes.ContainerPort::{
                      , name = Some "http"
                      , containerPort = 80
                      }
                    ]
                  , volumeMounts = Some
                      (makeVolumeMountsForKeyVaults app.keyVaultSecrets)
                  }
                , kubernetes.Container::{
                  , name = "dotnet-monitor"
                  , image = Some
                      "mcr.microsoft.com/dotnet/monitor:${dotnetMonitorVersion}"
                  }
                ]
              , nodeSelector = Some
                  (toMap { `kubernetes.azure.com/agentpool` = app.nodePool })
              , volumes = Some (makeVolumesForKeyVaults app.keyVaultSecrets)
              }
            }
          }
        }

let makeDotNetApplication
    : DotNetApplication.Type -> List KubernetesManifest
    = -- Make the entire application (deployment, configmap, service, secretproviderclass and ingress)
      \(app : DotNetApplication.Type) ->
          [ KubernetesManifest.Deployment (makeDeployment app)
          , KubernetesManifest.ConfigMap (makeConfigMap app)
          , KubernetesManifest.Service (makeWebService app)
          ]
        # ( if    app.webConfiguration.enabled
            then  [ KubernetesManifest.Ingress (makeWebIngress app) ]
            else  [] : List KubernetesManifest
          )
        # makeAzureKeyVaultSecretProviderClasses app

in  { makeDotNetApplication
    , DotNetApplication
    , ConfigElement
    , KeyVaultSecrets
    , Image
    , WebConfiguration
    }
