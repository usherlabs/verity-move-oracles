# Oracles for Aptos

## Deploy Aptos Oracles Contract

1. `aptos init` — to create an account. You can provide a shared Private Key.

2. **Compile**

```bash
aptos move compile --named-addresses verity=default,verity_test_foreign_module=default
```

3. **Publish smart sontract**

```bash
aptos move publish --named-addresses verity=default,verity_test_foreign_module=default
```

## Send New Request Transaction

Send a new request transaction to have it indexed. Make sure to replace placeholders with actual values relevant to your setup.

```bash
aptos move run --function-id  0x694cbe655b126e9e6a997e86aaab39e538abf30a8c78669ce23a98740b47b65d::example_caller::request_data --sender-account default --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:I want you to generate a comprehensive, in-depth document that contains at least 64,000 characters (approximately 10,000–12,000 words). The topic is:\nThe History, Technology, and Future of Artificial Intelligence\nThe document must be structured in a clear, hierarchical format using headings (H1, H2, H3), bullet points, numbered lists, and rich explanations. Include examples, case studies, detailed analysis, citations (real or realistic), historical context, current trends, challenges, and future outlooks.\nBreak it into well-organized sections, and ensure no part of the topic is left unexplored. The goal is to create an authoritative, exhaustive guide or report suitable for expert-level readers.\nDo not stop until you have generated at least 64,000 characters. You may begin now.' --args 'string:.' --args 'address:6b516ae2eb4aac47ffadd502cf19ce842020f515f1abea3e154cfc053ab3ab9a'
```
