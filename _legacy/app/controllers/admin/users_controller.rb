class Admin::UsersController < ApplicationController
   before_action :set_user, only: [:show, :edit, :update, :destroy]
   before_filter :authenticate_user!
   before_action :check_account_type

   def index
      @users = User.all
      respond_to do |format|
        format.html
        format.json { render json: UserDatatable.new(params, view_context: view_context) }
      end
   end

   def edit

   end

   def update
     respond_to do |format|
       if @user.update(user_params)
         format.html { redirect_to admin_users_path, notice: 'User was successfully updated.' }
         format.json { render :index, status: :ok, location: @user }
       else
         format.html { render :edit }
         format.json { render json: @user.errors, status: :unprocessable_entity }
       end
     end
   end

   def set_user
      @user = User.find(params[:id])
   end

   def check_account_type
      if current_user && !current_user.is_admin
         redirect_to base_url
      end
   end

   def user_params
     params.require(:user).permit(:user_name, :name, :email, :level, :password, :is_manager, :is_admin, :is_editor, :approved)
   end
end
