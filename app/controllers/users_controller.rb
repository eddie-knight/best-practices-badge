# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :require_admin,  only: %i[index destroy]
  before_action :logged_in_user, only: %i[edit update]
  before_action :correct_user,   only: %i[edit update]
  include SessionsHelper

  def new
    @user = User.new
  end

  def index
    @users = User.all.paginate(page: params[:page])
  end

  def show
    @user = User.find(params[:id])
    @projects = @user.projects.paginate(page: params[:page])
    return unless @user == current_user && @user.provider == 'github'
    @edit_projects = Project.where(repo_url: github_user_projects) - @projects
  end

  # rubocop: disable Metrics/MethodLength
  def create
    @user = User.find_by(email: user_params[:email])
    if @user
      redirect_existing
    else
      @user = User.new(user_params)
      @user.provider = 'local'
      if @user.save
        send_activation
      else
        render 'new'
      end
    end
  end
  # rubocop: enable Metrics/MethodLength

  def edit
    @user = User.find(params[:id])
    # Force redirect if current_user cannot edit.  Otherwise, the process
    # of displaying the edit fields (with their defaults) could cause an
    # unauthorized exposure of an email address.
    redirect_to @user unless current_user_can_edit(@user)
  end

  def update
    @user = User.find(params[:id])
    if @user.update_attributes(user_params)
      # Changes in: @user.previous_changes which returns hash in this form:
      # {"email"=>["karoldmunoz@BAD.gmail.com", "karoldmunoz@gmail.com"], ...}
      # Don't share password_digest or updated_at.  Instead:
      # name, email, locale; maybe the fact that password_digest changed.
      flash[:success] = t('.profile_updated')
      redirect_to @user
    else
      render 'edit'
    end
  end

  # rubocop: disable Metrics/MethodLength, Metrics/AbcSize
  def destroy
    # We don't do a lot of checking because only admins can run this,
    # but we'll try to prevent some disasters.
    id_to_delete = params[:id]
    user_to_delete = User.find(id_to_delete) # Exception raised if not found
    if current_user.id == user_to_delete.id
      flash[:danger] = t('.cannot_delete_self')
    else
      # Admin acquires ownership of remaining projects, if any,
      # so projects always have an owner (maintain invariant).
      # rubocop: disable Rails/SkipsModelValidations
      Project.where('user_id = ?', id_to_delete)
             .update_all(user_id: current_user.id)
      # rubocop: enable Rails/SkipsModelValidations
      user_to_delete.destroy
      flash[:success] = t('.user_deleted')
    end
    redirect_to users_url
  end
  # rubocop: enable Metrics/MethodLength, Metrics/AbcSize

  def redirect_existing
    if @user.activated
      flash[:info] = t('users.redirect_existing')
      redirect_to login_url
    else
      regenerate_activation_digest
      send_activation
    end
  end

  def send_activation
    @user.send_activation_email
    flash[:info] = t('users.new_activation_link_created')
    redirect_to root_url
  end

  private

  def user_params
    params.require(:user).permit(
      :provider, :uid, :name, :email, :password,
      :password_confirmation
    )
  end

  def require_admin
    redirect_to root_url unless current_user && current_user.admin?
  end

  # Confirms a logged-in user.
  def logged_in_user
    return if logged_in?
    flash[:danger] = t('users.please_log_in')
    redirect_to login_url
  end

  # Return true if current_user can edit account 'user'
  def current_user_can_edit(user)
    return false if !current_user
    user == current_user || current_user.admin?
  end

  # Confirms the correct user.
  def correct_user
    @user = User.find(params[:id])
    redirect_to(root_url) unless current_user_can_edit(@user)
  end

  def regenerate_activation_digest
    @user.activation_token = User.new_token
    @user.activation_digest = User.digest(@user.activation_token)
    @user.save!(touch: false)
  end
end
