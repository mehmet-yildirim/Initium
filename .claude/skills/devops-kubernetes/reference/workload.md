# Hardened workload manifests

A stateless HTTP service that passes Pod Security Standards `restricted`. The base references the
image by name; each overlay pins the digest with Kustomize `images:` (see `gitops.md`), so the
rendered manifest always deploys `image@sha256:...`.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  labels:
    app.kubernetes.io/name: app
spec:
  # replicas omitted: the HPA owns the count (GitOps would otherwise fight it)
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app
    spec:
      serviceAccountName: app
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: app
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: app
      containers:
        - name: app
          image: ghcr.io/acme/app          # digest pinned by the overlay
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: DATABASE_PASSWORD_FILE
              value: /var/run/secrets/app/db-password
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              memory: 256Mi                # equal to request; no CPU limit
          startupProbe:
            httpGet: { path: /health/live, port: http }
            periodSeconds: 2
            failureThreshold: 30
          readinessProbe:
            httpGet: { path: /health/ready, port: http }
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /health/live, port: http }
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              sleep:
                seconds: 5
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: db
              mountPath: /var/run/secrets/app
              readOnly: true
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 64Mi
        - name: db
          secret:
            secretName: app-db             # created by the ExternalSecret
            items:
              - key: password
                path: db-password
---
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app.kubernetes.io/name: app
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: app
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

## NetworkPolicy: default deny, then allow

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-ingress-from-gateway
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: app
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: gateway-system
      ports:
        - { protocol: TCP, port: 3000 }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-egress-to-database
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: app
  policyTypes: ["Egress"]
  egress:
    - to:
        - ipBlock:
            cidr: 10.20.0.0/24             # managed database subnet
      ports:
        - { protocol: TCP, port: 5432 }
```

Check the DNS pod labels for your distribution (`k8s-app: kube-dns` covers CoreDNS on most
clusters). Egress to cloud APIs usually needs FQDN-aware policy (Cilium `toFQDNs`) or an egress
gateway.
