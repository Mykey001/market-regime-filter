# How to Get a Valid NVIDIA API Key

## The Issue

The API key provided appears to be invalid or expired. NVIDIA API keys are tied to specific accounts and models.

## Solution: Get Your Own Free NVIDIA API Key

### Step 1: Create NVIDIA Account

1. Go to: https://build.nvidia.com/
2. Click "Sign In" or "Get Started"
3. Create a free NVIDIA account (or sign in if you have one)

### Step 2: Generate API Key

1. Once logged in, go to your account settings
2. Navigate to "API Keys" section
3. Click "Generate New API Key"
4. Copy the key (format: `nvapi-XXXXXXXXXXXX...`)

### Step 3: Find Available Models

1. Browse available models at: https://build.nvidia.com/explore/discover
2. Look for LLaMA models or code generation models
3. Popular options:
   - `meta/llama3-70b-instruct`
   - `meta/llama3-8b-instruct`
   - `mistralai/mixtral-8x7b-instruct-v0.1`
   - `nvidia/nemotron-4-340b-instruct` (if available)

### Step 4: Update Configuration

Once you have your API key:

1. Open: `EA_INTEGRATION\auto_integrate.py`
2. Find line 14:
   ```python
   NVIDIA_API_KEY = "your-old-key-here"
   ```
3. Replace with your new key:
   ```python
   NVIDIA_API_KEY = "nvapi-YOUR-NEW-KEY-HERE"
   ```
4. Update model name (line 24) if needed:
   ```python
   NVIDIA_MODEL = "meta/llama3-70b-instruct"  # Or model you chose
   ```
5. Save the file

### Step 5: Test Connection

```bash
test_api.bat
```

You should see: "✅ SUCCESS! API is working correctly"

## Alternative: Use Claude/ChatGPT API

If NVIDIA API doesn't work, you can modify the system to use:

### Option 1: OpenAI GPT-4
- Get key from: https://platform.openai.com/
- Model: `gpt-4` or `gpt-4-turbo`
- Change base_url to OpenAI's endpoint

### Option 2: Anthropic Claude
- Get key from: https://console.anthropic.com/
- Model: `claude-3-opus-20240229`
- Use Anthropic SDK instead of OpenAI

### Option 3: Local Model (Free, No API Key)
- Use Ollama with Code Llama
- 100% offline, no API needed
- Slower but free

## Quick Fix: Use Ollama Locally (Recommended!)

This is the BEST solution if you want to avoid API keys entirely!

### Install Ollama:

1. Download from: https://ollama.ai/
2. Install on Windows
3. Run: `ollama pull codellama:13b`

### Modify auto_integrate.py:

Replace the `integrate_with_ai()` function to use Ollama:

```python
def integrate_with_ai(ea_code, lib_code, logger):
    """Use LOCAL Ollama to integrate regime filter into EA"""
    
    logger.log("Preparing integration prompt for local AI...")
    prompt = create_integration_prompt(ea_code, lib_code)
    
    logger.log("Sending request to Ollama (local) - this may take 2-3 minutes...")
    
    try:
        import requests
        
        response = requests.post(
            'http://localhost:11434/api/generate',
            json={
                'model': 'codellama:13b',
                'prompt': prompt,
                'stream': False
            }
        )
        
        integrated_code = response.json()['response']
        
        # Clean up the response if it includes markdown code blocks
        if "```mql5" in integrated_code:
            integrated_code = integrated_code.split("```mql5")[1].split("```")[0].strip()
        elif "```" in integrated_code:
            integrated_code = integrated_code.split("```")[1].split("```")[0].strip()
        
        logger.success("Local AI integration completed successfully")
        return integrated_code
        
    except Exception as e:
        logger.error(f"Local AI integration failed: {str(e)}")
        raise
```

### Benefits of Ollama:
✅ 100% FREE  
✅ No API key needed  
✅ Works offline  
✅ Privacy (your code never leaves your computer)  
✅ Unlimited usage  

### Drawbacks:
⚠️ Slower (2-5 minutes per EA vs 30-60 seconds)  
⚠️ Requires ~8GB RAM  
⚠️ Requires ~10GB disk space  

## Troubleshooting API Issues

### Error: "Not Found for account"
- Your API key is invalid or expired
- Get a new key from NVIDIA Build

### Error: "Model not found"
- The model name is incorrect
- Check available models at https://build.nvidia.com/explore/discover

### Error: "Rate limit exceeded"
- Free tier has usage limits
- Wait and try again later
- Or upgrade to paid tier

### Error: "Authentication failed"
- API key is malformed
- Check for extra spaces or characters
- Regenerate key if needed

## Summary

**Easiest Solution:** Get free NVIDIA API key from https://build.nvidia.com/

**Best Solution:** Use Ollama locally (free, unlimited, private)

**Enterprise Solution:** Use OpenAI GPT-4 or Anthropic Claude (paid)

---

**Need help?** Check the main README.md or create an issue with your error message.
