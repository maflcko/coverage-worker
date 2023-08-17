# Standard Coverage Worker Image

Docker image for the standard coverage worker.

## How to use

### Required environment variables

* SCCACHE_GCS_KEY_PATH: Path to the GCS key file
* SCCACHE_GCS_BUCKET: Name of the GCS bucket for ccache storage
* SCCACHE_GCS_RW_MODE: Read/write mode for the GCS bucket (either `READ_WRITE` or `WRITE_ONLY`)
* CODECOV_TOKEN: Codecov token
* PR_NUM: Number of the pull request
