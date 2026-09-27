# docker buildx bake

One declarative build definition shared by developers and CI. Run `docker buildx bake` for the
default group, `docker buildx bake --print` to inspect the resolved config.

```hcl
# docker-bake.hcl
variable "REGISTRY" {
  default = "ghcr.io/acme"
}

variable "TAG" {
  default = "dev"
}

group "default" {
  targets = ["app"]
}

target "app" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "runtime"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REGISTRY}/app:${TAG}"]
  labels = {
    "org.opencontainers.image.source" = "https://github.com/acme/app"
  }
  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]
}
```

Rules:

- Local single-platform build into the image store:
  `docker buildx bake --set app.platform=linux/arm64 --load` (use your machine's platform).
- CI sets `TAG` to the commit SHA and adds a cache backend only there, so local builds never need
  registry credentials:
  `TAG=${GITHUB_SHA} docker buildx bake --push --set app.cache-from=type=gha --set app.cache-to=type=gha,mode=max`.
  `type=gha` works inside GitHub Actions through `docker/bake-action` (pinned by SHA; pass the
  overrides via its `set` input and read the digest from its `metadata` output). Other CI systems
  use `type=registry,ref=<registry>/app:buildcache`.
- `mode=max` provenance records build parameters and materials; review it once to confirm no
  secrets are passed as build args (they would appear in provenance).
- Multi-platform builds need QEMU or native builders; prefer native arm64 runners over emulation
  for speed.
- Attestations are pushed with the image index. Inspect them with
  `docker buildx imagetools inspect <image>@<digest> --format '{{ json .Provenance }}'`.
