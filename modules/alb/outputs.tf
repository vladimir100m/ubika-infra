output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group."
  value       = aws_security_group.alb.id
}

output "http_listener_arn" {
  description = "ARN of the HTTP (port 80) listener."
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS (port 443) listener."
  value       = aws_lb_listener.https.arn
}

output "target_group_arns" {
  description = "Map of target group key → ARN."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}
