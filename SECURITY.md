# Security policy

Report vulnerabilities privately through GitHub's **Report a vulnerability** feature for this repository. If private reporting is unavailable, open an issue asking for a private contact channel without disclosing exploit details. Do not include live credentials or private project contents in reports.

Supported versions are the current release and the current `main` branch. We will triage reports, coordinate a fix and disclosure with the reporter, and publish an updated image when warranted.

The development container is for trusted users and projects. The editor has shell access, the home volume retains agent credentials, and the workspace bind mount is writable. Keep the editor disabled unless needed, use TLS and authentication when exposed, and never mount the Docker socket into the dev container. Rotate credentials if the home volume or editor account is compromised.
