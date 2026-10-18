terraform {
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the target Kubernetes cluster."
  type        = string
  default     = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

resource "helm_release" "web_app" {
  name             = "web-release"
  chart            = abspath("${path.module}/../prod-web-app")
  namespace        = "production"
  create_namespace = true

  values = [
    file("${path.module}/production.yaml")
  ]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
}
