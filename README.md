# Kubernetes Deployment Master

The referenced repository showing two ways to deploy the same Helm chart to an
Amazon EKS cluster:

1. **Terraform** manages the Helm release as infrastructure.
2. **GitHub Actions** validates the chart and deploys it with Helm after a push
   to `main`.

The chart deploys the unprivileged NGINX container as a sample HTTP service.
Replace its image and application-specific probes/configuration for your own
application before using it in production. The sample deliberately contains
no passwords, cloud credentials, or real DNS names.

## Repository layout

```text
k8s-deployment-master/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── prod-web-app/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── ingress.yaml
│       ├── pdb.yaml
│       ├── service.yaml
│       └── serviceaccount.yaml
└── terraform/
    ├── main.tf
    └── production.yaml
```

## Prerequisites

- An EKS cluster and an AWS identity authorized to access it.
- Helm 3, Terraform 1.6 or later, AWS CLI, and GitHub CLI for local workflows.
- For the Actions workflow: an AWS IAM role configured for GitHub OIDC and
  EKS access for that role. Configure repository variables
  `AWS_ROLE_ARN`, `AWS_REGION`, and `EKS_CLUSTER_NAME`.
- A production GitHub environment named `production` if you want to use
  environment approvals or environment-scoped variables.

## Validate the chart locally

From the repository root:

```sh
helm lint ./prod-web-app
helm template web-release ./prod-web-app -f terraform/production.yaml
```

## Method 1: Terraform

Terraform manages the Helm release and records it in Terraform state. Use a
remote, encrypted, access-controlled backend with locking for shared or
production use; do not commit Terraform state or plan files.

1. Configure AWS credentials and Kubernetes access for the target EKS cluster.
   The provider reads `~/.kube/config` by default; override it with
   `-var="kubeconfig_path=C:/path/to/config"` if needed.
2. From the repository root, initialize and review the plan:

   ```sh
   terraform -chdir=terraform init
   terraform -chdir=terraform plan
   ```

3. Apply only after reviewing the plan:

   ```sh
   terraform -chdir=terraform apply
   ```

4. Verify the release:

   ```sh
   helm list --namespace production
   kubectl get deployments,services,pods --namespace production
   ```

To remove resources managed by this Terraform configuration, review and run
`terraform -chdir=terraform destroy`. Do not use `helm upgrade` or the GitHub
Actions deploy workflow to manage this same release while Terraform owns it.

## Method 2: GitHub Actions with Helm

The workflow runs lint and render checks on pull requests and pushes. A push to
`main` deploys `prod-web-app` to EKS using `helm upgrade --install`, `--atomic`,
and `--wait`.

1. In AWS, configure an IAM OIDC identity provider for GitHub Actions and a role
   whose trust policy is restricted to this repository (and preferably the
   `production` GitHub environment). Grant it only the AWS/EKS permissions
   required to connect to the cluster and deploy into the target namespace.
2. In GitHub, add repository variables `AWS_ROLE_ARN`, `AWS_REGION`, and
   `EKS_CLUSTER_NAME`. Configure the `production` environment if using one.
   The workflow uses OIDC; do not add long-lived AWS access keys.
3. Push a reviewed change to `main`. The deploy step creates the namespace if
   needed, waits for rollout, and fails atomically if deployment does not
   succeed.
4. Check the **Actions** tab and verify the release:

   ```sh
   helm status web-release --namespace production
   kubectl get deployments,services,pods --namespace production
   ```

For a manual rollback, inspect history and select a known-good revision:

```sh
helm history web-release --namespace production
helm rollback web-release REVISION --namespace production --wait
```

## Choosing a deployment owner

| Consideration | Terraform | GitHub Actions + Helm |
| --- | --- | --- |
| Best fit | Coordinating releases with infrastructure and reviewing desired state | Frequent application releases triggered by Git changes |
| State | Terraform state tracks the Helm release; use a secure remote backend | Helm release history is stored in the cluster |
| Rollback | Revert configuration and apply a reviewed Terraform plan | Roll back to a previous Helm revision |
| Operational needs | Terraform state, locking, and provider lifecycle | GitHub OIDC, workflow permissions, and cluster access |
| Main caution | Avoid out-of-band changes that drift from Terraform state | Restrict deploy permissions and protect the deployment branch/environment |

**Recommendation:** use Terraform for cluster and shared infrastructure, and
choose one owner for each application release. For a team already operating
Terraform as the source of truth for application releases, use Terraform.
Otherwise, GitHub Actions with OIDC and Helm is a straightforward CI/CD path.
Do not let Terraform and the Actions workflow manage the same Helm release.

## Production checklist

- Replace the sample NGINX image with an immutable, reviewed application image
  (prefer a digest) and configure correct health-check paths and ports.
- Set ingress hostnames, ingress class, TLS, and required cluster controllers
  explicitly; ingress is disabled by default.
- Review resource requests/limits, replica and autoscaling limits, Pod
  disruption settings, and security context against the application.
- Use an external secret manager or a separately managed Kubernetes Secret
  for credentials. Never commit credentials or plaintext secrets in values
  files. Terraform may persist Helm values in state, so protect state as
  sensitive data.
- Test in a non-production cluster before enabling production deployment.
