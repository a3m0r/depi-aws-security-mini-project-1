# ---------------------------------------------------------------------------
# Task 13 - CloudFront in front of the load balancer
# ---------------------------------------------------------------------------

# The secret that only CloudFront knows. It lives in the state file - keep the state private.
resource "random_password" "origin_secret" {
  length  = 32
  special = false
}

# Short cache so you still see the two servers alternate while testing.
resource "aws_cloudfront_cache_policy" "short" {
  name        = "${var.project_name}-short-cache"
  comment     = "Cache for at most 60 seconds"
  min_ttl     = 0
  default_ttl = 30
  max_ttl     = 60

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  comment         = "${var.project_name} front door"
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_100"

  origin {
    origin_id   = "alb"
    domain_name = aws_lb.main.dns_name

    # CloudFront -> ALB over HTTP (the ALB has no certificate in this lab).
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # The secret header the ALB rule checks.
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_secret.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.short.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Free *.cloudfront.net certificate -> HTTPS with a padlock.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Standard logging into the logs bucket.
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.logs,
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_policy.logs,
  ]
}
