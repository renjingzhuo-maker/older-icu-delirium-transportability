# Data Governance

## Restricted Data

MIMIC-IV and eICU-CRD are credentialed-access clinical databases distributed
through PhysioNet. Their files are not redistributed in this repository.

Do not commit or upload:

- original database files or database dumps;
- patient-, admission-, ICU-stay-, caregiver-, or hospital-level extracts;
- exported analysis CSV files;
- patient-level predictions or trajectory memberships;
- fitted model objects trained from restricted data;
- logs containing source rows, identifiers, local credentials, or access URLs;
- screenshots or notebooks displaying individual records.

The repository `.gitignore` blocks common forms of these files, but each
contributor remains responsible for reviewing staged files before every commit.

## Allowed Public Content

The intended public content is limited to:

- SQL extraction and quality-assurance code;
- statistical-analysis and visualization code;
- environment and dependency specifications;
- study protocol and methodological documentation;
- manuscript-generation code;
- disclosure-safe aggregate findings already intended for publication.

## Local Storage

Run the pipeline only in an access-controlled local environment. Store generated
patient-level files in `data/` and model outputs in `results/`; both directories
are excluded from Git.

Use local credential mechanisms such as `.pgpass`, environment variables, or an
interactive prompt. Never place passwords, PhysioNet sessions, cookies, or API
tokens in repository files.

## Sharing Derived Resources

Before sharing a derived dataset or fitted model, review the current PhysioNet
rules for the source database. MIMIC guidance states that derived datasets and
models should be treated as sensitive and, when shared, should be distributed
through PhysioNet under the same agreement as the source data.

## Incident Response

If restricted content is committed:

1. Do not merely delete it in a later commit.
2. Make the repository private immediately.
3. Revoke exposed credentials or sessions.
4. Remove the material from Git history.
5. Review the incident under the applicable PhysioNet agreement before making
   the repository public again.
