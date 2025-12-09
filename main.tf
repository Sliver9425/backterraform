provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Proyecto = "Examen-Universidad"
      Creador  = "Quezada"
    }
  }
}

# --- 1. DATOS ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SECURITY GROUP ---
resource "aws_security_group" "web_sg" {
  name        = "sg_proyecto_terraform"
  description = "Permitir HTTP y SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress { 
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. LOAD BALANCER (ALB) ---
resource "aws_lb" "mi_alb" {
  name               = "alb-proyecto-terraform"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "mi_tg" {
  name     = "tg-proyecto-terraform"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mi_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mi_tg.arn
  }
}

# --- 4. LAUNCH TEMPLATE ---
resource "aws_launch_template" "mi_lt" {
  name_prefix   = "lt-proyecto-"
  
  # TU AMI
  image_id      = "ami-0736eae96b470121f" 
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  # IMPORTANTE: Recuerda que para que el CI/CD funcione con Docker Hub
  # necesitas el script user_data aquí. Si tu AMI ya lo tiene, ignora esto.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    until systemctl is-active --quiet docker; do sleep 1; done
    docker rm -f $(docker ps -aq) || true
    # Asegúrate de poner TU usuario y TU imagen correcta aquí abajo:
    docker pull Sliver9425/examen-docker:latest
    docker run -d --restart always -p 80:80 Sliver9425/examen-docker:latest
  EOF
  )
}

# --- 5. AUTO SCALING GROUP ---
resource "aws_autoscaling_group" "mi_asg" {
  name                = "asg-proyecto-terraform"
  desired_capacity    = 3
  max_size            = 3
  min_size            = 2
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.mi_tg.arn]

  launch_template {
    id      = aws_launch_template.mi_lt.id
    version = "$Latest"
  }
  
  instance_refresh {
    strategy = "Rolling"
  }
}

# ==========================================
# --- 6. REGLAS DE ESCALADO (LAS 3 NUEVAS) ---
# ==========================================

# 6.1. REGLA POR CPU (Procesador > 50%)
resource "aws_autoscaling_policy" "cpu_policy" {
  name                   = "escalar-por-cpu"
  autoscaling_group_name = aws_autoscaling_group.mi_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0 
  }
}

# 6.2. REGLA POR RED (Tráfico > 1MB)
resource "aws_autoscaling_policy" "network_policy" {
  name                   = "escalar-por-red"
  autoscaling_group_name = aws_autoscaling_group.mi_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }
    target_value = 1000000.0 
  }
}

# 6.3. REGLA POR MEMORIA RAM (Uso > 60%)
# Nota: Para que esta funcione, la AMI debe tener instalado el CloudWatch Agent
resource "aws_autoscaling_policy" "memory_policy" {
  name                   = "escalar-por-memoria"
  autoscaling_group_name = aws_autoscaling_group.mi_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    customized_metric_specification {
      metric_name = "mem_used_percent"
      namespace   = "CWAgent"
      statistic   = "Average"
      unit        = "Percent"
      
      metric_dimension {
        name  = "AutoScalingGroupName"
        value = aws_autoscaling_group.mi_asg.name
      }
    }
    target_value = 60.0 
  }
}
