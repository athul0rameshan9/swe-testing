"""Smoke test: can we reach the GPT-4o deployment on Azure through LiteLLM?

Loads settings from .env and sends one tiny "Say hello" request.
Never prints the API key.

Run with:  ./venv/bin/python test_azure.py
"""
import os
import sys
import time

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

REQUIRED = ["AZURE_API_KEY", "AZURE_API_BASE", "AZURE_API_VERSION", "AZURE_DEPLOYMENT_NAME"]
missing = [name for name in REQUIRED if not os.getenv(name)]
if missing:
    sys.exit(f"Missing values in .env: {', '.join(missing)}")

key = os.environ["AZURE_API_KEY"]
base = os.environ["AZURE_API_BASE"]
version = os.environ["AZURE_API_VERSION"]
deployment = os.environ["AZURE_DEPLOYMENT_NAME"]

# A common mistake is pasting the whole "Target URI" instead of just the endpoint.
if "/openai/deployments" in base or "api-version=" in base:
    sys.exit(
        "AZURE_API_BASE looks like a full Target URI.\n"
        "Keep only the start, e.g. https://<my-resource>.openai.azure.com/\n"
        "and put the api-version value in AZURE_API_VERSION instead."
    )

# Azure AI Foundry "model inference" endpoints need a different LiteLLM provider.
provider = "azure_ai" if "services.ai.azure.com/models" in base else "azure"
model = f"{provider}/{deployment}"

print(f"Provider:    {provider}")
print(f"Model:       {model}")
print(f"Endpoint:    {base}")
print(f"API version: {version}")
print("API key:     (set, hidden)")

import litellm  # imported late so a bad .env fails fast

start = time.time()
try:
    response = litellm.completion(
        model=model,
        messages=[{"role": "user", "content": "Say hello"}],
        api_key=key,
        api_base=base,
        api_version=version,
        temperature=0.0,
        max_tokens=20,
    )
except Exception as e:
    # Scrub the key in case an error message ever echoes it back.
    print(f"\nFAILED ({type(e).__name__}): {str(e).replace(key, '***')}")
    sys.exit(1)

print(f"\nReply:       {response.choices[0].message.content!r}")
print(f"Model used:  {response.model}")
print(f"Tokens:      {response.usage.prompt_tokens} in / {response.usage.completion_tokens} out")
print(f"Time:        {time.time() - start:.1f}s")
print("\nSUCCESS")
