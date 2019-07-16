variable "do_token" {}
variable "region" { default = "tor1" }
variable "os" { default = "ubuntu-19-04-x64" }
variable "private_adapter" { default  = "ens4" }

variable "pd_size" { default = "s-8vcpu-32gb" }
variable "pd_count" { default = 1 }
variable "pd_first_image" { default  = "pingcap/pd:v2.1.14" }
variable "pd_second_image" { default  = "pingcap/pd:v3.0.0" }

variable "tikv_size" { default = "s-8vcpu-32gb" }
variable "tikv_count" { default  = 3 }
variable "tikv_first_image" { default  = "pingcap/tikv:v2.1.14" }
variable "tikv_second_image" { default  = "pingcap/tikv:v3.0.0" }

variable "ycsb_size" { default = "s-8vcpu-32gb" }
variable "ycsb_count" { default  = 3 }
variable "ycsb_operationcount" { default  = 1000000 }
variable "ycsb_recordcount" { default  = 1000000 }
variable "ycsb_api" { default  = "raw" }
variable "ycsb_threads" { default = 3000 }
variable "ycsb_fieldcount" { default = 10 }
variable "ycsb_fieldlength" { default = 100 }
variable "ycsb_distribution" { default = "zipfian" }
variable "ycsb_conncount" { default = 128 }
variable "ycsb_batchsize" { default = 128 }

// Tweaking below here may lead to unexpected results.

provider "digitalocean" { token = "${var.do_token}" }

// PD bootstrap
resource "digitalocean_droplet" "pd" {
    name = "pd"
    size = "${var.pd_size}"
    region = "${var.region}"
    image = "${var.os}"
    ssh_keys = ["${digitalocean_ssh_key.bencher.fingerprint}"]
    private_networking = true

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.pd.ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/pd.service", {
                private_adapter = var.private_adapter,
                image = var.pd_first_image,
                bootstrap = ""
            })}
        EOF
        destination = "/etc/systemd/system/pd-first.service"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/pd.service", {
                private_adapter = var.private_adapter,
                image = var.pd_second_image,
                bootstrap = ""
            })}
        EOF
        destination = "/etc/systemd/system/pd-second.service"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/pd-config.toml", {
            })}
        EOF
        destination = "/etc/pd.toml"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/sysctl.conf", {
            })}
        EOF
        destination = "/etc/sysctl.conf"
    }

    provisioner "remote-exec" {
        inline = [
            "apt-get update --yes",
            "apt-get upgrade --yes",
            "apt-get install docker.io --yes",
            "sysctl --system",
            "systemctl enable docker --now",
            "docker pull ${var.pd_first_image}",
            "docker pull ${var.pd_second_image}",
            "systemctl start pd-first",
        ]
    }
}

// TiKV

resource "digitalocean_droplet" "tikv" {
    name = "tikv-${count.index}"
    count = "${var.tikv_count}"
    size = "${var.tikv_size}"
    region = "${var.region}"
    image = "${var.os}"
    ssh_keys = ["${digitalocean_ssh_key.bencher.fingerprint}"]
    private_networking = true

    connection {
        type     = "ssh"
        host     = "${self.ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/tikv.service", {
                image = var.tikv_first_image,
                private_adapter = var.private_adapter,
                pd = digitalocean_droplet.pd,
            })}
        EOF
        destination = "/etc/systemd/system/tikv-first.service"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/tikv.service", {
                image = var.tikv_second_image,
                private_adapter = var.private_adapter,
                pd = digitalocean_droplet.pd,
            })}
        EOF
        destination = "/etc/systemd/system/tikv-second.service"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/tikv-config.toml", {})}
        EOF
        destination = "/etc/tikv.toml"
    }

    provisioner "file" {
        content = <<EOF
            ${templatefile("files/sysctl.conf", {
            })}
        EOF
        destination = "/etc/sysctl.conf"
    }

    provisioner "remote-exec" {
        inline = [
            "apt-get update --yes",
            "apt-get upgrade --yes",
            "apt-get install docker.io --yes",
            "sysctl --system",
            "systemctl enable docker --now",
            "docker pull ${var.tikv_first_image}",
            "docker pull ${var.tikv_second_image}",
            "systemctl start tikv-first",
        ]
    }
}

// YCSB
resource "digitalocean_droplet" "ycsb" {
    name = "ycsb-${count.index}"
    count = "${var.ycsb_count}"
    size = "${var.ycsb_size}"
    region = "${var.region}"
    image = "${var.os}"
    ssh_keys = ["${digitalocean_ssh_key.bencher.fingerprint}"]
    private_networking = true

    depends_on = [digitalocean_droplet.tikv, digitalocean_droplet.pd, digitalocean_droplet.pd]

    connection {
        type     = "ssh"
        host     = "${self.ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }
    
    provisioner "file" {
        content = <<EOF
            ${templatefile("files/sysctl.conf", {
            })}
        EOF
        destination = "/etc/sysctl.conf"
    }

    provisioner "remote-exec" {
        inline = [
            "apt-get update --yes",
            "apt-get upgrade --yes",
            "apt-get install docker.io --yes",
            "sysctl --system",
            "systemctl enable docker --now",
        ]
    }
}

resource "null_resource" "ycsb_first" {
    count = "${var.ycsb_count}"
    triggers = {
        pre = "${join(",", digitalocean_droplet.ycsb.*.id)}"
    }
    depends_on = [digitalocean_droplet.ycsb]

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.ycsb[count.index].ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "remote-exec" {
        inline = [
            "mkdir -p /results-first-${count.index}",
            "docker run --name=ycsb-first-load-workloada --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloada -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-first-run-workloada --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloada -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-first-load-workloada > /results-first-${count.index}/load-workloada",
            "docker logs ycsb-first-run-workloada > /results-first-${count.index}/run-workloada",
            //
            "docker run --name=ycsb-first-load-workloadb --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloadb -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-first-run-workloadb --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloadb -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-first-load-workloadb > /results-first-${count.index}/load-workloadb",
            "docker logs ycsb-first-run-workloadb > /results-first-${count.index}/run-workloadb",
            //
            "docker run --name=ycsb-first-load-workloadc --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloadc -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-first-run-workloadc --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloadc -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-first-load-workloadc > /results-first-${count.index}/load-workloadc",
            "docker logs ycsb-first-run-workloadc > /results-first-${count.index}/run-workloadc",
        ]
    }

    
    provisioner "local-exec" {
        command = <<EOF
            scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i key root@${digitalocean_droplet.ycsb[count.index].ipv4_address}:/results-first-${count.index} results-first-${count.index}
        EOF
    }
}

resource "null_resource" "stop_pd" {
    triggers = {
        ycsb = "${join(",", null_resource.ycsb_first.*.id)}"
    }
    depends_on = [null_resource.ycsb_first]

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.pd.ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "remote-exec" {
        inline = [
            "systemctl stop pd-first",
        ]
    }
}

resource "null_resource" "change_tikv" {
    count = "${var.tikv_count}"
    triggers = {
        pre = "${null_resource.stop_pd.id}"
    }
    depends_on = [null_resource.stop_pd]

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.tikv[count.index].ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "remote-exec" {
        inline = [
            "systemctl stop tikv-first",
            "systemctl start tikv-second",
        ]
    }
}

resource "null_resource" "start_pd" {
    triggers = {
        pre = "${join(",", null_resource.change_tikv.*.id)}"
    }
    depends_on = [null_resource.change_tikv]

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.pd.ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "remote-exec" {
        inline = [
            "systemctl start pd-second",
        ]
    }
}

resource "null_resource" "ycsb_second" {
    count = "${var.ycsb_count}"
    triggers = {
        pre = "${null_resource.start_pd.id}"
    }
    depends_on = [null_resource.start_pd]

    connection {
        type     = "ssh"
        host     = "${digitalocean_droplet.ycsb[count.index].ipv4_address}"
        user     = "root"
        private_key = "${file("key")}"
    }

    provisioner "remote-exec" {
        inline = [
            "mkdir -p /results-second-${count.index}",
            "docker run --name=ycsb-second-load-workloada --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloada -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-second-run-workloada --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloada -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-second-load-workloada > /results-second-${count.index}/load-workloada",
            "docker logs ycsb-second-run-workloada > /results-second-${count.index}/run-workloada",
            //
            "docker run --name=ycsb-second-load-workloadb --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloadb -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-second-run-workloadb --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloadb -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-second-load-workloadb > /results-second-${count.index}/load-workloadb",
            "docker logs ycsb-second-run-workloadb > /results-second-${count.index}/run-workloadb",
            //
            "docker run --name=ycsb-second-load-workloadc --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb load tikv -P workloads/workloadc -p dropdata=true -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution} -p insertstart=${floor(var.ycsb_recordcount / var.ycsb_count) * count.index} -p insertcount=${floor(var.ycsb_recordcount / var.ycsb_count)}",
            "docker run --name=ycsb-second-run-workloadc --init --network=host --sysctl net.ipv4.tcp_syncookies=0 --sysctl net.core.somaxconn=32768 pingcap/go-ycsb run tikv -P workloads/workloadc -p verbose=false -p tikv.conncount=${var.ycsb_conncount} -p tikv.type=${var.ycsb_api} -p tikv.batchsize=${var.ycsb_batchsize} -p tikv.pd=${digitalocean_droplet.pd.ipv4_address_private}:2379 -p operationcount=${var.ycsb_operationcount} -p recordcount=${var.ycsb_recordcount} -p threadcount=${var.ycsb_threads} -p fieldcount=${var.ycsb_fieldcount} -p fieldlength=${var.ycsb_fieldlength} -p requestdistribution=${var.ycsb_distribution}",
            "docker logs ycsb-second-load-workloadc > /results-second-${count.index}/load-workloadc",
            "docker logs ycsb-second-run-workloadc > /results-second-${count.index}/run-workloadc",
        ]
    }

    provisioner "local-exec" {
        command = <<EOF
            scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i key root@${digitalocean_droplet.ycsb[count.index].ipv4_address}:/results-second-${count.index} results-second-${count.index}
        EOF
    }
    
}

// General
resource "digitalocean_ssh_key" "bencher" {
  name       = "TiKV Bencher"
  public_key = "${file("key.pub")}"
}