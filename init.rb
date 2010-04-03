require 'redmine'

Redmine::Plugin.register :redmine_version_burndown do
  name 'Redmine Version Burndown Charts plugin'
  author 'Dai Fujihara'
  description 'Version Burndown Charts Plugin is graphical chart plugin for Scrum.'
  author_url 'http://daipresents.com/weblog/fujihalab/'
  url 'http://daipresents.com/weblog/fujihalab/archives/2010/02/redmine-version-burndown-charts-plugin-release.php '

  requires_redmine :version_or_higher => '0.9.0'
  version '0.0.5'

  project_module :version_burndown_charts do
    permission :version_burndown_charts_view, :version_burndown_charts => :index
  end

  menu :project_menu, :version_burndown_charts, { :controller => 'version_burndown_charts', :action => 'index' },
  :caption => :version_burndown_charts, :after => :activity, :param => :project_id
end
