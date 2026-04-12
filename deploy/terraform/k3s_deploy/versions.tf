terraform {
  required_version = ">= 1.6.0"

  backend "s3" {}

  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = ">= 0.140.0"
    }
  }
}