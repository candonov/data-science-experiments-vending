variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "EKS Cluster Name and the VPC name"
  type        = string
  default     = "ai-ml"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes Version"
  default     = "1.29"
}

variable "capacity_type" {
  type        = string
  description = "Capacity SPOT or ON_DEMAND"
  default     = "SPOT"
}

variable "kubecost_token" {
  type        = string
  description = "To find or obtain Kubecost token, go to https://www.kubecost.com/install#show-instructions"
}

variable "enable_upbound_aws_provider" {
  type        = bool
  description = "Installs the upbound aws provider"
  default     = true
}

variable "enable_aws_provider" {
  type        = bool
  description = "Installs the contrib aws provider"
  default     = false
}

variable "enable_kubernetes_provider" {
  type        = bool
  description = "Installs the kubernetes provider"
  default     = true
}

variable "enable_helm_provider" {
  type        = bool
  description = "Installs the helm provider"
  default     = false
}
