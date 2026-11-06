## Deployment change

- Environment(s):
- Change type: image promotion / configuration / platform / policy

## Checklist

- [ ] `validate` workflow green (render + kubeconform for every environment)
- [ ] Images referenced by digest only
- [ ] No secrets in values (Key Vault references only)
- [ ] Rollback: revert this PR
