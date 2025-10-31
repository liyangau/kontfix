# Kontfix

Kontfix is an opinionated framework for managing Kong Control Planes on Konnect powered by Nix ([terranix](https://github.com/terranix/terranix)). It leverages Nix modules to dynamically generate Terraform resources for managing control planes, system accounts, and client certificate lifecycles.

![](./assets/kontfix.png)

## Features

- **Declarative Configuration**: Define Kong Control Plane setups declaratively with minimal configuration.
- **Reproducibility**: Achieve consistent configurations across multiple region and environments.
- **Flexibility**: Support different configurations for each control planes while providing sensible defaults.
- **Integration**: Seamlessly integrate with CI/CD pipelines for Terraform workflows. 

## Getting Started

To get start, please refer to [How to Use Kontfix to Manage Kong Konnect Control Planes](https://tech.aufomm.com/how-to-use-kontfix-to-manage-kong-konnect-control-planes/)

## WIP

- [ ] Kontfix Manual
- [x] Example for CI/CD integration. You can find an example [here](https://github.com/aufomm/kontfix-examples).
- [ ] More tests

## License

This project is licensed under the [GPL-3.0 license](LICENSE).
