You'll need a DO API token (free credit link:), `openssh` (with `scp`), and `terraform` to run this benchmark.

First, you'll need to roll an SSH key next into the `key` and `key.pub` files.

```bash
ssh-keygen -t ed25519 -f key
```

Second, you need to initialize Terraform.

```bash
terraform init
```

Finally, you can run the benchmark with `terraform apply`.

You'll find results in `results-first` and `results-second` folders. By default, first is `2.1.14`, second is `3.0.0`.