class UpdateSourceRankWorker
  include Sidekiq::Worker
  sidekiq_options :queue => :low, unique: :until_executed

  def perform(project_id)
    project = Project.find_by_id(project_id)
    project.update_source_rank if project
  end
end
