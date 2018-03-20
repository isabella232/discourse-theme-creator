# name: discourse-theme-creator
# about: Allows users to create and share their own themes.
# version: 0.1
# author: David Taylor dtaylor.uk
# url: https://www.github.com/davidtaylorhq/discourse-theme-creator

register_asset 'theme_creator.js'
register_asset "stylesheets/theme-creator.scss"

load File.expand_path('../lib/theme_creator/engine.rb', __FILE__)

Discourse::Application.routes.append do
  mount ::ThemeCreator::Engine, at: "/user_themes"
  get "u/:username/themes" => "users#index", constraints: { username: RouteFormat.username }
  get "u/:username/themes/:id" => "users#index", constraints: { username: RouteFormat.username }
  get "u/:username/themes/:theme_id/colors/:color_scheme_id" => "users#index", constraints: { username: RouteFormat.username }
  get 'u/:username/themes/:id/:target/:field_name/edit' => 'users#index', constraints: { username: RouteFormat.username }
end

after_initialize do

  # Override guardian to allow users to preview their own themes using the ?preview_theme_key= variable
  add_to_class(:guardian, :allow_theme?) do |theme_key|
    return true if Theme.user_theme_keys.include?(theme_key) # Is a 'user selectable theme'
    return false if not Theme.theme_keys.include?(theme_key) # Is not a valid theme

    # If you own the theme, you are allowed to view it using GET param
    # Even staff are not allowed to use GET to access other user's themes, to reduce XSS attack risk
    can_hotlink_user_theme? Theme.find_by(key: theme_key)
  end

  add_to_class(:guardian, :can_hotlink_user_theme?) do |theme|
    is_my_own?(theme)
  end

  add_to_class(:guardian, :can_see_user_theme?) do |theme|
    return true if is_staff?

    return true if is_my_own?(theme)

    # Theme is shared and theme owner has permission to share
    theme.is_shared && User.find(theme.user_id).guardian.can_share_user_theme?(theme)
  end

  add_to_class(:guardian, :can_edit_user_theme?) do |theme|
    is_staff? || is_my_own?(theme)
  end

  add_to_class(:guardian, :can_share_user_theme?) do |theme|
    return true if SiteSetting.theme_creator_share_groups.blank? # all users can share

    # Check if user is in any allowed groups
    allowed_groups = SiteSetting.theme_creator_share_groups.split("|")
    @user.groups.where(name: allowed_groups).exists?
  end

  # Add methods so that a theme can be shared/unshared by the user
  add_to_class(:theme, :is_shared) do 
    PluginStore.get('discourse-theme-creator', "share:$#{id}") == true
  end

  add_to_class(:theme, :is_shared=) do |val|
    PluginStore.set('discourse-theme-creator', "share:$#{id}", val==true)
  end

  add_to_serializer(:theme, :is_shared) do
    object.is_shared
  end

  add_to_serializer(:theme, :can_share) do
    User.find(object.user_id).guardian.can_share_user_theme?(object)
  end
  
  # Allow preview of shared user themes
  # flash[:user_theme_key] will only be populated after a POST request
  # after a UI confirmation (theme_creator_controller.rb) to prevent hotlinking
  reloadable_patch do |plugin|
    class ::ApplicationController
      module ThemeCreatorOverrides
        def handle_theme
          super()
          user_theme_key = flash[:user_theme_key]
          if user_theme_key && 
             Theme.theme_keys.include?(user_theme_key) && # Has requested a valid theme
             guardian.can_see_user_theme?(Theme.find_by(key: user_theme_key))
                @theme_key = request.env[:resolved_theme_key] = user_theme_key
          end
        end
      end
      prepend ThemeCreatorOverrides
    end
  end


end


