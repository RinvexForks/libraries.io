class ProjectsController < ApplicationController
  before_action :ensure_logged_in, only: [:your_dependent_repos, :mute, :unmute]

  def index
    if current_user
      muted_ids = params[:include_muted].present? ? [] : current_user.muted_project_ids
      @versions = current_user.all_subscribed_versions.where.not(project_id: muted_ids).where.not(published_at: nil).newest_first.includes(:project).paginate(per_page: 20, page: params[:page])
      @projects = current_user.recommended_projects.limit(7)
      render 'dashboard/home'
    else
      facets = Project.facets(:facet_limit => 30)

      @languages = facets[:languages][:terms]
      @platforms = facets[:platforms][:terms]
      @licenses = facets[:licenses][:terms].reject{ |t| t.term.downcase == 'other' }
      @keywords = facets[:keywords][:terms]
    end
  end

  def bus_factor
    if params[:language].present?
      @language = Project.language(params[:language].downcase).first.try(:language)
      raise ActiveRecord::RecordNotFound if @language.nil?
      scope = Project.language(@language)
    else
      scope = Project
    end

    @languages = Project.bus_factor.group('language').order('language').pluck('language').compact
    @projects = scope.bus_factor.order('github_repositories.github_contributions_count ASC, projects.rank DESC, projects.created_at DESC').paginate(page: params[:page], per_page: 20)
  end

  def unlicensed
    if params[:platform].present?
      find_platform(:platform)
      raise ActiveRecord::RecordNotFound if @platform_name.nil?
      scope = Project.platform(@platform_name)
    else
      scope = Project
    end

    @platforms = Project.unlicensed.with_dependents.not_deprecated.group('platform').order('platform').pluck('platform').compact
    @projects = scope.unlicensed.with_dependents.not_deprecated.order('dependents_count DESC, rank DESC, projects.created_at DESC').paginate(page: params[:page], per_page: 20)
  end

  def show
    find_project
    if incorrect_case?
      if params[:number].present?
        return redirect_to(version_path(@project.to_param.merge(number: params[:number])), :status => :moved_permanently)
      else
        return redirect_to(project_path(@project.to_param), :status => :moved_permanently)
      end
    end
    find_version
    @dependencies = (@versions.length > 0 ? (@version || @versions.first).dependencies.includes(:project).order('project_name ASC').limit(100) : [])
    @contributors = @project.contributors.order('count DESC').visible.limit(20)
  end

  def about
    find_project
    find_version
    send_data render_to_string(:about, layout: false), filename: "#{@project.platform.downcase}-#{@project}.ABOUT", type: 'application/text', disposition: 'attachment'
  end

  def dependents
    find_project
    page = params[:page].to_i > 0 ? params[:page].to_i : 1
    @dependents = WillPaginate::Collection.create(page, 30, @project.dependents_count) do |pager|
      pager.replace(@project.dependent_projects(page: page))
    end
  end

  def dependent_repos
    find_project
    @dependent_repos = @project.dependent_repositories.open_source.paginate(page: params[:page])
  end

  def your_dependent_repos
    find_project
    @dependent_repos = current_user.your_dependent_repos(@project).paginate(page: params[:page])
  end

  def versions
    find_project
    if incorrect_case?
      return redirect_to(project_versions_path(@project.to_param), :status => :moved_permanently)
    else
      @versions = @project.versions.newest_first.paginate(page: params[:page])
      respond_to do |format|
        format.html
        format.atom
      end
    end
  end

  def tags
    find_project
    if incorrect_case?
      return redirect_to(project_tags_path(@project.to_param), :status => :moved_permanently)
    else
      if @project.github_repository.nil?
        @tags = []
      else
        @tags = @project.github_tags.published.order('published_at DESC').paginate(page: params[:page])
      end
      respond_to do |format|
        format.html
        format.atom
      end
    end
  end

  def mute
    find_project
    current_user.mute(@project)
    redirect_to_back_or_default project_path(@project.to_param)
  end

  def unmute
    find_project
    current_user.unmute(@project)
    redirect_to_back_or_default project_path(@project.to_param)
  end

  private

  def incorrect_case?
    params[:platform] != params[:platform].downcase || (@project && params[:name] != @project.name)
  end

  def find_version
    @version_count = @project.versions.newest_first.count
    @github_repository = @project.github_repository
    if @version_count.zero?
      @versions = []
      if @github_repository.present?
        @github_tags = @github_repository.github_tags.published.order('published_at DESC').limit(10).to_a.sort
        if params[:number].present?
          @version = @github_repository.github_tags.published.find_by_name(params[:number])
          raise ActiveRecord::RecordNotFound if @version.nil?
        end
      else
        @github_tags = []
      end
      if @github_tags.empty?
        raise ActiveRecord::RecordNotFound if params[:number].present?
      end
    else
      @versions = @project.versions.newest_first.to_a.first(10).sort
      if params[:number].present?
        @version = @project.versions.find_by_number(params[:number])
        raise ActiveRecord::RecordNotFound if @version.nil?
      end
    end
    @version_number = @version.try(:number) || @project.latest_release_number
  end
end
