output "web_servers_public_ip" {
    value = aws_instance.web_servers.*.public_ip
}

output "db_servers_private_ip" {
    value = aws_instance.db_servers.*.private_ip
}

output "lb_dns_name" {
    value = aws_elb.main_lb.dns_name
}
