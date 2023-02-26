resource "aws_security_group" "ec2-for-efs-mt-sg" {
  name        = "${var.project_name}-${var.stage}-efs-ec2-sg"
  description = "Amazon EFS, SG for EC2 instance"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.base_cidr_block}/16", "${data.external.my-ip.result["ip"]}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-efs-ec2-sg"
  }
}

resource "aws_security_group" "efs-mt-sg" {
  name        = "${var.project_name}-${var.stage}-mt-sg"
  description = "Amazon EFS, SG for mount target"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    cidr_blocks     = []
    security_groups = [aws_security_group.ec2-for-efs-mt-sg.id]
  }

  tags = {
    Name = "${var.project_name}-${var.stage}-mt-sg"
  }
}

#resource "aws_key_pair" "key-pair" {
#  public_key = ""
#  key_name   = "${var.project_name}-${var.stage}-key-pair"
#}
#
#resource "aws_instance" "ec2-for-efs-mt" {
#  instance_type               = "t2.micro"
#  ami                         = "ami-0eec024dbbe865d48"
#  associate_public_ip_address = false
#  key_name                    = "${var.project_name}-${var.stage}-key-pair"
#  vpc_security_group_ids      = [aws_security_group.ec2-for-efs-mt-sg.id]
#  subnet_id                   = aws_subnet.private-subnet-1.id
#
#  tags = {
#    Name = "${var.project_name}-${var.stage}-ec2-for-efs-mt"
#  }
#}