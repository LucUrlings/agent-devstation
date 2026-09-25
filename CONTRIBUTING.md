# Contributing

Thanks for helping improve Agent Devstation. Open an issue for behavior changes before a large pull request. Keep changes focused and add a short explanation of user impact.

Work on a feature branch and open a pull request against `main`. Run `docker compose config -q`, build the image for your available architecture, and run `IMAGE=<local-tag> bash tests/smoke.sh` when your change affects the image or startup. Say which architecture and SDKs you tested. Account based Remote Control pairing requires a manual test and must not use CI secrets.

Never commit `.env`, workspace projects, API keys, login files, or the `state/` and `secrets/` directories. Respect upstream tool licenses. Original contributions to this repository are provided under Apache License 2.0.

Be constructive and follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
