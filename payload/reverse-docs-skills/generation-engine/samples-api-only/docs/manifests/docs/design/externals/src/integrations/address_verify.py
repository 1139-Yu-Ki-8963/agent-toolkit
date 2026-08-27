import requests


def address_verify(address, api_key):
    return requests.post(
        "https://address.example.test/v1/verify",
        json={"address": address},
        headers={"Authorization": f"Bearer {api_key}"},
    )
