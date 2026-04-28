class Users::OmniauthController < Devise::RegistrationsController
  def facebook
    @user = User.create_from_facebook_data(request.env['omniauth.auth'])
    if @user.persisted?
      cookies['login_provider'] =  'facebook'
      sign_in_and_redirect @user
    else
      flash[:error] = "There was a problem signing you in through Facebook. Please register or try signing in later. Error: <b>#{@user.errors.full_messages} for #{@user.provider}</b>"
      redirect_to new_user_registration_url
    end
  end

  def github
    @user = User.create_from_github_data(request.env['omniauth.auth'])
    if @user.persisted?
      cookies['login_provider'] =  'github'
      sign_in_and_redirect @user
    else
      flash[:error] = "There was a problem signing you in through Github. Please register or try signing in later. Error: <b>#{@user.errors.full_messages} for #{@user.provider}</b>"
      redirect_to new_user_registration_url
    end
  end

  def google_oauth2
    @user = User.create_from_google_data(request.env['omniauth.auth'])
    if @user.persisted?
      cookies['login_provider'] =  'google'
      sign_in_and_redirect @user
    else
      flash[:error] = "There was a problem signing you in through Google. Please register or try signing in later. Error: <b>#{@user.errors.full_messages} for #{@user.provider}</b>"
      redirect_to new_user_registration_url
    end
  end

  def failure
    flash[:notice] = ""
    redirect_to root_path
  end
end
