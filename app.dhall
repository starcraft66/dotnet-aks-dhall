let lib = ./lib/dotnetapp.dhall

let sample =
      lib.DotNetApplication::{
      , name = "sample-function-app"
      , image = lib.Image::{
        , registry = "myregistry.azurecr.io"
        , name = "samples/dotnet"
        , tag = "exampleTag"
        }
      , replicas = 3
      , nodePool = "default"
      , config =
        [ lib.ConfigElement::{ key = "EventHub__Name", value = "something" }
        , lib.ConfigElement::{
          , key = "EventHub__ConsumerGroup"
          , value = "something-consumer-group"
          }
        , lib.ConfigElement::{
          , key = "ServiceBus__TopicName"
          , value = "sbt-something-dev-01"
          }
        , lib.ConfigElement::{
          , key = "ServiceBus__SubscriptionName"
          , value = "sbts-something-dev-01"
          }
        ]
      , keyVaultSecrets =
        [ lib.KeyVaultSecrets::{
          , keyVaultName = "app-secrets-1"
          , secrets =
            [ lib.ConfigElement::{
              , key = "EventHub__ConnectionString"
              , value = "event-hub-connection-string"
              }
            , lib.ConfigElement::{
              , key = "ServiceBus__ConnectionString"
              , value = "service-bus-connection-string"
              }
            , lib.ConfigElement::{
              , key = "AzureWebJobsStorage"
              , value = "webjobs-storage-account-connection-string"
              }
            , lib.ConfigElement::{
              , key = "AzureWebJobsDashboard"
              , value = "webjobs-storage-account-connection-string"
              }
            ]
          }
        ]
      , webConfiguration = lib.WebConfiguration::{
        , enabled = True
        , tls = True
        , hosts = [ "www.example.com", "www2.example.com" ]
        }
      }

in  lib.makeDotNetApplication sample
