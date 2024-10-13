# Oracles for Aptos

## Send New Request Transaction

Send a new request transaction to have it indexed. Make sure to replace placeholders with actual values relevant to your setup.

```bash
aptos move run --function-id  0xa2b7160c0dc70548e8105121b075df9ea3b98c0c82294207ca38cb1165b94f59::example_caller::request_data --sender-account default --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:{}' --args 'string:.data.public_metrics.followers_count' --args 'address:6b516ae2eb4aac47ffadd502cf19ce842020f515f1abea3e154cfc053ab3ab9a'
```
