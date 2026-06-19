# Google OAuth Setup Guide for BiteWorthy

## Step-by-Step Instructions

### 1. Go to Google Cloud Console
Visit: https://console.cloud.google.com/

### 2. Create a New Project (or select existing)
- Click the project dropdown at the top
- Click "New Project"
- Name it: "BiteWorthy" 
- Click "Create"

### 3. Enable Google+ API
- In the left sidebar, click "APIs & Services" → "Library"
- Search for "Google+ API"
- Click on it and press "Enable"

### 4. Configure OAuth Consent Screen
- Go to "APIs & Services" → "OAuth consent screen"
- Choose "External" user type
- Click "Create"
- Fill in the required fields:
  - **App name**: BiteWorthy
  - **User support email**: Your email
  - **App domain**: bite-worthy.com
  - **Authorized domains**: bite-worthy.com
  - **Developer contact**: Your email
- Click "Save and Continue"
- On Scopes page, click "Add or Remove Scopes"
- Select these scopes:
  - `.../auth/userinfo.email`
  - `.../auth/userinfo.profile`
  - `openid`
- Click "Update" then "Save and Continue"
- Add test users if needed (for testing before app verification)
- Click "Save and Continue"

### 5. Create OAuth 2.0 Credentials
- Go to "APIs & Services" → "Credentials"
- Click "Create Credentials" → "OAuth client ID"
- Choose "Web application"
- Name it: "BiteWorthy Web Client"
- Add Authorized JavaScript origins:
  - `http://localhost:3000`
  - `https://bite-worthy.com`
- Add Authorized redirect URIs:
  - `http://localhost:3000/users/auth/google_oauth2/callback`
  - `https://bite-worthy.com/users/auth/google_oauth2/callback`
- Click "Create"

### 6. Copy Your Credentials
A popup will show your credentials:
- **Client ID**: Copy this (looks like: xxxxx.apps.googleusercontent.com)
- **Client Secret**: Copy this (keep it secret!)

### 7. Add to Your .env File
```bash
GOOGLE_CLIENT_ID=paste_your_client_id_here
GOOGLE_CLIENT_SECRET=paste_your_client_secret_here
```

### 8. Test It Out
1. Start your Rails server: `rails server`
2. Visit http://localhost:3000/users/sign_in
3. Click "Continue with Google"
4. You should see Google's login page
5. After logging in, you'll be redirected back to BiteWorthy

## Important Notes

### For Development
- The localhost URLs will work immediately
- No domain verification needed

### For Production
- You'll need to verify domain ownership
- Add your production domain DNS TXT record when prompted
- May need to submit for OAuth verification if:
  - You have > 100 users
  - You request sensitive scopes
  - Your app is public

### Security Tips
- Never commit your Client Secret to git
- Keep .env in .gitignore
- Use different OAuth apps for dev/staging/production
- Rotate credentials if exposed

## Troubleshooting

### "Redirect URI mismatch" error
- Double-check the callback URL matches exactly
- Make sure you added both http (dev) and https (prod) versions
- Check for trailing slashes

### "This app isn't verified" warning
- Normal for development
- Add yourself as a test user in OAuth consent screen
- For production, submit for verification

### Google sign-in not working
- Check browser console for errors
- Verify API is enabled
- Check credentials are in .env file
- Restart Rails server after adding .env variables

## Quick Test URLs
- Google Cloud Console: https://console.cloud.google.com/
- Your OAuth Credentials: https://console.cloud.google.com/apis/credentials
- OAuth Consent Screen: https://console.cloud.google.com/apis/credentials/consent

Need help? Check the Rails logs for detailed error messages!