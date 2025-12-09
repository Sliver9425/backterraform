output "url_del_sitio" {
  description = "Copia y pega esta URL en tu navegador"
  value       = "http://${aws_lb.mi_alb.dns_name}"
}

output "nombre_asg" {
  description = "Nombre del grupo de autoescalado"
  value       = aws_autoscaling_group.mi_asg.name
}