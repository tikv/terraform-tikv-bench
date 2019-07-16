You'll need a DO API token ([$50 credit referral](https://m.do.co/c/b6156cf29450)), `openssh` (with `scp`), and `terraform` to run this benchmark. You can get these tools from your friendly package manager. (Don't have one? [Win](https://scoop.sh/)/[Mac](https://brew.sh/))

First, you'll need to roll an SSH key next into the `key` and `key.pub` files.

```bash
ssh-keygen -t ed25519 -f key
```

Second, you need to initialize Terraform.

```bash
terraform init
```

Third, you'll need to set up your `./terraform.tfvars` file.

```tf
do_token="Your_token_goes_here"
```

Finally, you can run the benchmark:

```bash
# Warning: This **will** cost you money hourly until you run `terraform destroy`
terraform apply
```

You'll find results in `results-first` and `results-second` folders. By default, first is `2.1.14`, second is `3.0.0`.

After, **make sure to run** `terraform destroy` so you don't get additional charges.

# Knobs

There are various knobs you can tweak in your `terraform.tfvars`. For a full list of knobs you can look at the variables in the `bench.tf` file.

**Warning:** Scaling `pd` is not supported yet.

You can scale the number of `tikv` nodes:

```tf
tikv_count = 1
```

You can change the docker images benchmarked:

```tf
tikv_image = "you/tikv:latest"
pd_image = "you/pd:latest"
```

You can change the machine sizes as well (find the valid sizes with `doctl compute size list` from the `doctl` utility):

```tf
tikv_size = "s-4vcpu-8gb"
pd_size = "s-4vcpu-8gb"
```