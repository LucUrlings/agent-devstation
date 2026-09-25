# Repository settings for publication

After the first pull request is ready, create a GitHub ruleset targeting `main`:

1. Require a pull request before merging.
2. Require the `image-and-sdk-smoke` and `arm64-build` CI jobs to pass. Keep required checks tied to the CI workflow in this repository.
3. Require all review conversations to be resolved.
4. Block force pushes and deletion of `main`.
5. If a second trusted maintainer is available, require one approval from someone other than the author. For a solo maintainer, leave the approval count at zero so the maintainer can merge a passing, reviewed PR without a lockout.

Keep the CI workflow read-only for pull requests, including forks. Do not add repository secrets to PR jobs. The image publishing workflow uses `packages: write` only for trusted pushes to `main` and published full releases. Wait for the `main` publish workflow to finish before creating a release, and point its version tag at that merged commit. Check the GHCR package visibility after the first nightly publish; set it to public if necessary so `docker compose pull` works without a registry login.
