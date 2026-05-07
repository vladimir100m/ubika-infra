resource "aws_s3_object" "litellm_compose" {
  bucket = module.config_bucket.bucket_id
  key    = "bootstrap/docker-compose.yaml"
  source = "${path.module}/../docker-compose.yaml"
  etag   = filemd5("${path.module}/../docker-compose.yaml")
}

resource "aws_s3_object" "litellm_config_yaml" {
  bucket = module.config_bucket.bucket_id
  key    = "bootstrap/config.yaml"
  source = "${path.module}/../config/config.yaml"
  etag   = filemd5("${path.module}/../config/config.yaml")
}

# Templated after LiteLLM EC2 exists (private IP in upstream).
resource "aws_s3_object" "nginx_edge" {
  bucket = module.config_bucket.bucket_id
  key    = "bootstrap/nginx-edge.conf"
  content = templatefile("${path.module}/nginx-edge.conf.tpl", {
    litellm_private_ip = module.litellm_ec2.private_ip
  })

  depends_on = [module.litellm_ec2]
}
