resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name}-${var.environment}-ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs-tasks.amazonaws.com" ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-${var.environment}-ecsTaskRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs.amazonaws.com","ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "secrets" {
  name        = "${var.name}-${var.environment}-task-policy-ssm"
  description = "Policy that allows access to SSM"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment-for-ssm" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.secrets.arn
}

resource "aws_cloudwatch_log_group" "main" {
  name_prefix = "/ecs/${var.name}-task-${var.environment}-"
  retention_in_days = 1

  tags = {
    Name        = "${var.name}-task-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.name}-task-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([{
    name        = "${var.name}-container-${var.environment}"
    image       = "${var.container_image}:${var.tag}"
    essential   = true
    environment = var.container_environment
    portMappings = [{
      protocol      = "tcp"
      containerPort = var.container_port
      hostPort      = var.container_port
      }
    ]
    environment = [
      {
        "name" : "DATABASE",
        "value" : var.environment
      },
      {
        "name" : "DATABASE_URL",
        "value" : ""
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.main.name
        awslogs-stream-prefix = "ecs"
        awslogs-region        = var.region
      }
    }
    #secrets = var.container_secrets
  }])

  tags = {
    Name        = "${var.name}-task-${var.environment}"
    Environment = var.environment
  }
}
resource "aws_ecs_cluster" "main" {
  name = "${var.name}-cluster-${var.environment}"
  tags = {
    Name        = "${var.name}-cluster-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_ecs_service" "main" {
  name                               = "${var.name}-service-${var.environment}"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.main.arn
  desired_count                      = var.service_desired_count
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 300
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  network_configuration {
    security_groups  = var.ecs_service_security_groups
    subnets          = var.subnets.*.id
    assign_public_ip = true
  }

  force_new_deployment = true
  load_balancer {
    target_group_arn = var.aws_alb_target_group_arn[0].arn
    container_name   = "${var.name}-container-${var.environment}"
    container_port   = var.container_port
  }
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  depends_on = [var.aws_alb_listener]
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  name               = "memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_iam_role" "codedeploy_service" {

  name = "codedeploy-service-${var.name}-${var.environment}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codedeploy_service" {
  role       = aws_iam_role.codedeploy_service.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
resource "aws_codedeploy_app" "this" {
  compute_platform = "ECS"
  name             = "${var.name}-${var.environment}-deploy"
}

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.name}-${var.environment}-deploy-group"
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  #deployment_config_name = "CodeDeployCustomECSCanary50Percent3Minutes"
  service_role_arn       = aws_iam_role.codedeploy_service.arn

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "STOP_DEPLOYMENT"
      wait_time_in_minutes = 30
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.main.name
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.aws_alb_listener.arn]
      }

      target_group {
        name = var.aws_alb_target_group_arn[0].name
      }

      target_group {
        name = var.aws_alb_target_group_arn[1].name
      }
    }
  }
}