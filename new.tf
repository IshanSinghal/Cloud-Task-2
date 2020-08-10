provider "aws" {
	region = "ap-south-1"
	profile = "ishan_tf"
}

// SEC GROUP
resource "aws_security_group" "sgc2" {
  name        = "sgc2"
  description = "Allow inbound traffic ssh and http"

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "FOR NFS"
    protocol   = "tcp"
    from_port  = 2049
    to_port    = 2049
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh_httpd_NFS"
  }
}

//CREATE INSTANCE
resource "aws_instance" "webserver" {
    depends_on = [ aws_security_group.sgc2 ]
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	key_name = "keyt"
	security_groups =["${aws_security_group.sgc2.name}"]
	
	connection {
	type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/ishan/Desktop/cloudt2/keyt.pem")
    host     = aws_instance.webserver.public_ip
	}
  
	provisioner "remote-exec" {
		inline = [
		"sudo yum install httpd  php git -y",
		"sudo yum install -y amazon-efs-utils",
		"sudo systemctl restart httpd",
		"sudo systemctl enable httpd",
		]
	}

	tags = {
		Name = "webos"
	}
}

//CREATE EFS
resource "aws_efs_file_system" "efs" {
  depends_on = [ aws_instance.webserver ]
  creation_token = "efstoken"

  tags = {
    Name = "myefs"
  }
}

//MOUNT EFS
resource "aws_efs_mount_target" "efs" {

  depends_on = [ aws_efs_file_system.efs ]
  file_system_id = aws_efs_file_system.efs.id
  subnet_id = aws_instance.webserver.subnet_id
  security_groups = [ aws_security_group.sgc2.id ]

}


//GET IP OF INSTANCE
output "myos_ip" {
  value = aws_instance.webserver.public_ip
}

resource "null_resource" "storeInstanceIP"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.webserver.public_ip} > publicip.txt"
  	}
}


//MOUNT EFS and GIT CLONE
resource "null_resource" "mountAndgithub"  {

	depends_on = [ aws_efs_mount_target.efs	]


	connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/ishan/Desktop/cloudt2/keyt.pem")
    host     = aws_instance.webserver.public_ip
	}

	provisioner "remote-exec" {
		inline = [
		"sudo mount -t '${aws_efs_file_system.efs.id}':/ /var/www/html",
		"sudo rm -rf /var/www/html/*",
		"sudo git clone https://github.com/IshanSinghal/multicloud.git /var/www/html/"
		]
	}
}


resource "aws_s3_bucket" "c2s3" {
 bucket = "c2s3"
 }
resource "aws_s3_bucket_policy" "c2s3" {
depends_on = [
		aws_s3_bucket.c2s3,
	]  
bucket = aws_s3_bucket.c2s3.id

  policy = <<POLICY
{
  "Id": "Policy1380877762691",
  "Statement": [
    {
      "Sid": "Stmt1380877761162",
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::c2s3/*",
      "Principal": {
        "AWS": [
          "*"
        ]
      }
    }
  ]
}
POLICY
}

//TRIGGER JENKINS TO S3 FILES FROM GITHUB
resource "null_resource" "jenkinsS3"  {

	depends_on = [
		aws_s3_bucket_policy.c2s3,
	]	

	provisioner "local-exec" {
	    command = "chrome 192.168.1.4:8080/job/multicloudgithubtos3/build?token=redhat"
  	}
}

resource "aws_cloudfront_distribution" "tera-cloufront2" {
depends_on = [
	null_resource.jenkinsS3,
]

 origin {
 domain_name = aws_s3_bucket.c2s3.bucket_regional_domain_name
 origin_id = "S3-c2s3"
 custom_origin_config {
 http_port = 80
 https_port = 80
 origin_protocol_policy = "match-viewer"
 origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
 }
 }

 enabled = true
 is_ipv6_enabled     = true
 default_cache_behavior {
 allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
 cached_methods = ["GET", "HEAD"]
 target_origin_id = "S3-c2s3"
 forwarded_values {
 query_string = false

 cookies {
 forward = "none"
 }
 }
 viewer_protocol_policy = "allow-all"
 min_ttl = 0
 default_ttl = 3600
 max_ttl = 86400
 }

price_class = "PriceClass_All"

 restrictions {
 geo_restriction {

 restriction_type = "none"
}
 }
 viewer_certificate {
 cloudfront_default_certificate = true
 }
}


resource "null_resource" "changeurl"  {

	depends_on = [ aws_cloudfront_distribution.tera-cloufront2	]


	connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/ishan/Desktop/cloudt2/keyt.pem")
    host     = aws_instance.webserver.public_ip
	}

	provisioner "remote-exec" {
		inline = [
		"sudo sed -i 's+taws.png+http://${aws_cloudfront_distribution.tera-cloufront2.domain_name}/taws.png+g' /var/www/html/index.html"
		]
	}
}

resource "null_resource" "display"  {

    depends_on = [ null_resource.changeurl ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.webserver.public_ip}"
  	}
}



