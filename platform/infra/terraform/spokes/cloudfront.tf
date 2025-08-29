################################################################################
# CloudFront Distribution for Spoke Cluster Ingress NLB
################################################################################

# Reference the managed policies by name instead of ID
data "aws_cloudfront_cache_policy" "use_origin_cache_control_headers_query_strings" {
  name = "UseOriginCacheControlHeaders-QueryStrings"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# Data source to get the NLB created by ingress-nginx (deployed via ArgoCD)
# This will be available after the ingress-nginx addon is deployed
data "aws_lb" "ingress_nginx" {
  name = "${local.name}-ingress"
  
  # This depends on the ingress-nginx being deployed by ArgoCD
  # We'll handle the timing through the deploy script
}

resource "aws_cloudfront_distribution" "ingress" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${local.name} ingress NLB"
  price_class         = "PriceClass_All"
  http_version        = "http2"
  wait_for_deployment = false

  origin {
    domain_name = data.aws_lb.ingress_nginx.dns_name
    origin_id   = "http-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 30
    }

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }

    custom_header {
      name  = "X-Forwarded-Port"
      value = "443"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "http-origin"

    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    # Using policy names instead of hardcoded IDs
    cache_policy_id          = data.aws_cloudfront_cache_policy.use_origin_cache_control_headers_query_strings.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${local.name}-ingress-cloudfront"
    Environment = terraform.workspace
  }
}
