# GitHub and Zenodo Release Checklist

## Before the First Push

- [ ] Confirm that only the intended public release directory is used.
- [ ] Run the credential and restricted-file audit documented below.
- [ ] Review `git status --short` before committing.
- [ ] Confirm that `data/` and `results/` contain only their README files.
- [ ] Confirm that no database dump, compressed source file, model object, or
      patient-level output is staged.
- [ ] Confirm all four authors approve the public release.

## GitHub

1. Create a repository named `older-icu-delirium-transportability`.
2. Keep it private during the first upload and review.
3. Do not initialize the remote with a README, license, or `.gitignore`; these
   files are already included locally.
4. Add the remote and push the local `main` branch.
5. Review the repository through the GitHub web interface.
6. Make the repository public only after the disclosure review passes.

Suggested commands:

```powershell
git remote add origin https://github.com/USERNAME/older-icu-delirium-transportability.git
git push -u origin main
```

## Zenodo DOI

1. Sign in to Zenodo and connect the GitHub account.
2. Enable the repository in the Zenodo GitHub settings.
3. Update `CITATION.cff` with the final repository URL.
4. Create GitHub release `v1.0.0`.
5. Wait for Zenodo to archive the release and assign a DOI.
6. Add the version DOI to `CITATION.cff` and the manuscript Code Availability
   statement.
7. For future manuscript citations, prefer the Zenodo concept DOI when a stable
   citation across software versions is required.

## Local Audit Commands

```powershell
git status --short
git ls-files
git grep -n -i -E "password|passwd|token|secret|cookie|session"
git ls-files | Select-String -Pattern "\.(csv|tsv|parquet|joblib|pkl|rds|dump|backup|gz|zip)$"
```

The final command should return no restricted analytical or database files.
