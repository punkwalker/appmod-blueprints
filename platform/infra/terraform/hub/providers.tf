provider "aws" {
  region = "us-east-1"  # Région fixe pour éviter la dépendance circulaire
}

# Get cluster info from existing cluster
data "aws_eks_cluster" "cluster_for_providers" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster_for_providers" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster_for_providers.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster_for_providers.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster_for_providers.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster_for_providers.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster_for_providers.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster_for_providers.token
  }
}
