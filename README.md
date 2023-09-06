<h1 align="center">
  <br>
  <a href="https://btc-coverage.aureleoules.com"><img src="https://github.com/bitcoin-coverage/core/raw/master/docs/assets/logo.png" alt="Bitcoin Coverage" width="200"></a>
  <br>
    Coverage Worker
  <br>
</h1>

<h4 align="center">Runs test coverage jobs of <a href="https://github.com/bitcoin/bitcoin" target="_blank">Bitcoin Core</a> pull requests.</h4>

## 📖 Introduction
This repository contains the code of the worker that runs the coverage jobs of Bitcoin Core pull requests.

## 🚀 How it works
The worker executes the following steps:
1. Clone the Bitcoin Core repository
2. Checkout the pull request branch
3. Compile Bitcoin Core
5. Run the test coverage job
6. Upload the coverage report to S3 to be later parsed by [bitcoin-coverage/core](https://github.com/bitcoin-coverage/core).
7. Execute [chernobyl](https://github.com/bitcoin-coverage/chernobyl) to generate mutations
8. Upload the mutations report to S3 to be later parsed by [bitcoin-coverage/core](https://github.com/bitcoin-coverage/core) and then tested.

## 📦 Docker
This Docker image is automatically built and deployed to AWS ECR on every push to `master` branch.

## 📝 License

MIT - [Aurèle Oulès](https://github.com/aureleoules)
