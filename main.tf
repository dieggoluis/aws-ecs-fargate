# provider
provider "aws" {
  access_key = var.AWS_ACCESS_KEY
  secret_key = var.AWS_SECRET_KEY
  region     = var.AWS_REGION
}

# network
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc-name
  cidr = var.vpc-cidr

  azs             = var.azs
  public_subnets  = var.public-subnets
  private_subnets = var.private-subnets

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# ecs cluster
resource "aws_ecs_cluster" "this" {
  name = var.ecs-cluster
}

# task definition
resource "aws_iam_role" "execution" {
  name               = "execution-role"
  assume_role_policy = file("./policies/ecs-task-execution-role.json")
}

resource "aws_iam_role" "task" {
  name               = "task-role"
  assume_role_policy = file("./policies/ecs-task-execution-role.json")
}

resource "aws_iam_policy" "task-execution" {
  name = "task-execution-policy"

  policy = file("./policies/ecs-task-execution-role-policy.json")
}

resource "aws_iam_role_policy_attachment" "tasks_execution" {
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.task-execution.arn
}

resource "aws_ecs_task_definition" "service" {
  family                = "service"
  container_definitions = file("task-definitions/service.json")

  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  cpu                      = 256
  memory                   = 512

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# load balancer
resource "aws_security_group" "web" {
  vpc_id = module.vpc.vpc_id
  name   = "alb-security-group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_lb_target_group" "this" {
  name        = "load-balancer-target"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip" # required when network type is awsvpc, which is required by fargate launch time
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.this.arn
    type             = "forward"
  }
}

# ecs cluster service
resource "aws_security_group" "services" {
  vpc_id = module.vpc.vpc_id
  name   = "security-groups-services"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "this" {
  name            = "service-nginx"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  # required by awsvpc network mode
  network_configuration {
    security_groups = [aws_security_group.services.id]

    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "nginx"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_target_group.this, aws_lb_listener.this]
}

