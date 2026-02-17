# Snapshot Deployment (GitHub Actions + GitHub Pages)

This project now includes:

- Snapshot generator: `scripts/generate_snapshots.py`
- Scheduled workflow: `.github/workflows/snapshots.yml`

The workflow builds static JSON snapshots and deploys them to GitHub Pages.

## 1) Ensure required data files exist in the repo

The workflow expects:

- `data/buildings.geojson` (polygon footprints)
- `data/cafes_copenhagen.geojson`

`data/buildings.geojson` is ignored by `.gitignore`, so add it explicitly:

```bash
git add -f data/buildings.geojson
git add data/cafes_copenhagen.geojson
git commit -m "Add snapshot input data"
git push
```

## 2) Push workflow files

```bash
git add .github/workflows/snapshots.yml scripts/generate_snapshots.py .gitignore SNAPSHOT_DEPLOY.md
git commit -m "Add scheduled snapshot pipeline"
git push
```

## 3) Enable GitHub Pages

In GitHub repo settings:

- `Settings` -> `Pages`
- Source: `GitHub Actions`

## 4) Run once manually

- Open `Actions` tab
- Select `Build And Deploy Snapshots`
- Click `Run workflow`

After success, snapshots are available at:

- `https://<github-username>.github.io/<repo>/latest/index.json`
- `https://<github-username>.github.io/<repo>/latest/core-cph.json`
- `https://<github-username>.github.io/<repo>/latest/indre-by.json`
- `https://<github-username>.github.io/<repo>/latest/norrebro.json`
- `https://<github-username>.github.io/<repo>/latest/frederiksberg.json`
- `https://<github-username>.github.io/<repo>/latest/osterbro.json`

## 5) Update cadence

Workflow schedule is set to every 15 minutes (`*/15 * * * *`).

Adjust in `.github/workflows/snapshots.yml` if needed.
