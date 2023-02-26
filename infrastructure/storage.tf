resource "aws_efs_file_system" "fs" {
  tags = {
    Name = "${var.project_name}-${var.stage}-efs"
  }

  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

}

resource "aws_efs_access_point" "access-point-dags" {
  file_system_id = aws_efs_file_system.fs.id

  root_directory {
    path = "/dags"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "777"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

}

resource "aws_efs_access_point" "access-point-config" {
  file_system_id = aws_efs_file_system.fs.id

  root_directory {
    path = "/config"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "777"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }
}

resource "aws_efs_access_point" "access-point-logs" {
  file_system_id = aws_efs_file_system.fs.id

  root_directory {
    path = "/logs"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "777"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }
}


resource "aws_efs_access_point" "access-point-plugins" {
  file_system_id = aws_efs_file_system.fs.id

  root_directory {
    path = "/plugins"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "777"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }
}


resource "aws_efs_access_point" "access-point-files" {
  file_system_id = aws_efs_file_system.fs.id

  root_directory {
    path = "/files"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "777"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }
}

resource "aws_efs_mount_target" "efs-ec2-mount-target-1" {
  file_system_id  = aws_efs_file_system.fs.id
  subnet_id       = aws_subnet.private-subnet-1.id
  security_groups = [
    aws_security_group.scheduler.id,
    aws_security_group.workers.id,
    aws_security_group.web_server_ecs_internal.id
  ]
}

resource "aws_efs_mount_target" "efs-ec2-mount-target-2" {
  file_system_id  = aws_efs_file_system.fs.id
  subnet_id       = aws_subnet.private-subnet-2.id
  security_groups = [
    aws_security_group.scheduler.id,
    aws_security_group.workers.id,
    aws_security_group.web_server_ecs_internal.id
  ]
}


resource "aws_efs_mount_target" "efs-ec2-mount-target-3" {
  file_system_id  = aws_efs_file_system.fs.id
  subnet_id       = aws_subnet.public-subnet-1.id
  security_groups = [aws_security_group.efs-mt-sg.id]
}
