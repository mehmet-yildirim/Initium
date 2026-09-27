# Admission and namespace policies

## Namespace with Pod Security Standards

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app-production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
    gateway-access: public                 # lets the shared Gateway accept routes from here
```

Pin `enforce-version` to your current minor (for example `v1.36`) if you want upgrades to
tighten policy only after review.

## ValidatingAdmissionPolicy: images by digest

Built in (GA since 1.30), evaluated in the API server with CEL — no webhook to operate.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-image-digest
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments", "statefulsets", "daemonsets"]
  validations:
    - expression: >-
        object.spec.template.spec.containers.all(c, c.image.contains('@sha256:')) &&
        (!has(object.spec.template.spec.initContainers) ||
          object.spec.template.spec.initContainers.all(c, c.image.contains('@sha256:')))
      message: "Container images must be referenced by digest (image@sha256:...)."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-image-digest
spec:
  policyName: require-image-digest
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        pod-security.kubernetes.io/enforce: restricted
```

Roll out with `validationActions: ["Warn", "Audit"]` first, then switch to `Deny`.

## Kyverno ImageValidatingPolicy: cosign keyless signature

Requires Kyverno 1.19 (`policies.kyverno.io/v1`). The identity must match the workflow that runs
`cosign sign` in `devops-cicd` (`release-image.yml` on `main`).

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-release-signature
spec:
  validationActions: [Audit]               # switch to [Deny] once clean
  failurePolicy: Fail
  webhookConfiguration:
    timeoutSeconds: 15
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  matchImageReferences:
    - glob: "ghcr.io/acme/*"
  attestors:
    - name: release
      cosign:
        keyless:
          identities:
            - subject: "https://github.com/acme/app/.github/workflows/release-image.yml@refs/heads/main"
              issuer: "https://token.actions.githubusercontent.com"
        ctlog:
          url: https://rekor.sigstore.dev
  validations:
    - expression: >-
        images.containers.map(image, verifyImageSignatures(image, [attestors.release])).all(e, e > 0)
      message: "Image is not signed by the acme/app release workflow."
```

Notes:

- Test end to end on your registry while in `Audit`. Kyverno 1.19 has open issues verifying
  cosign v3 bundle-format signatures and attestations stored as OCI referrers on registries without
  the Referrers API; check the Kyverno issue tracker before switching to `Deny`.
- Exclude system namespaces explicitly with a `PolicyException` (`policies.kyverno.io`) rather
  than weakening the match.
- The Sigstore policy-controller is an alternative verifier if Kyverno is not already in use.
