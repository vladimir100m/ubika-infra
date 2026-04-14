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

resource "aws_s3_object" "litellm_nginx" {
  bucket = module.config_bucket.bucket_id
  key    = "bootstrap/nginx.conf"
  source = "${path.module}/../nginx/nginx.conf"
  etag   = filemd5("${path.module}/../nginx/nginx.conf")
}
