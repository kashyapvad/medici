require 'yaml'
require 'active_support/security_utils'
require 'sidekiq'
require 'sidekiq/web'

# Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
#   # Protect against timing attacks:
#   # - See https://codahale.com/a-lesson-in-timing-attacks/
#   # - See https://thisdata.com/blog/timing-attacks-against-string-comparison/
#   # - Use & (do not use &&) so that it doesn't short circuit.
#   # - Use digests to stop length information leaking
#   ActiveSupport::SecurityUtils.secure_compare(
#     ::Digest::SHA256.hexdigest(user),
#     ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_ADMIN_USER"])
#   ) &
#     ActiveSupport::SecurityUtils.secure_compare(
#       ::Digest::SHA256.hexdigest(password),
#       ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_ADMIN_PASSWORD"])
#     )
# end

SIDEKIQ_CONFIG = YAML::load(File.open('config/sidekiq.yml'))

# def sidekiq_size() sidekiq_workers_size + sidekiq_queue_size + sidekiq_retry_queue_size end
# def sidekiq_empty?() sidekiq_queue_empty? and sidekiq_workers_empty? and sidekiq_retry_queue_empty? end

# def sidekiq_dup_markers() global_redis_client.keys("w.*") end
# def sidekiq_dup_marker_size() sidekiq_dup_markers.count end
# def sidekiq_clear_dup_markers() sidekiq_dup_markers.each {|k| global_redis_client.del k} end

# def sidekiq_queue_size()       Sidekiq::Stats.new.enqueued     end
# def sidekiq_workers_size()     Sidekiq::Stats.new.workers_size end
# def sidekiq_retry_queue_size() Sidekiq::Stats.new.retry_size   end


# def sidekiq_queue_empty?()       Sidekiq::Stats.new.enqueued.zero?     end
# def sidekiq_workers_empty?()     Sidekiq::Stats.new.workers_size.zero? end
# def sidekiq_retry_queue_empty?() Sidekiq::Stats.new.retry_size.zero?   end

# def sidekiq_purge_scheduled_jobs!
#   x = Sidekiq::ScheduledSet.new
#   x.map &:delete
# end

# def sidekiq_clear_stats!
#   Sidekiq::Stats.new.reset('processed', 'failed', 'retries', 'scheduled')
#   sidekiq_clear_stats_for_dead!
# end

# def sidekiq_clear_stats_for_processed!
#   Sidekiq::Stats.new.reset('processed')
# end

# def sidekiq_clear_stats_for_failed!
#   Sidekiq::Stats.new.reset('failed')
# end

# def sidekiq_clear_stats_for_retries!
#   Sidekiq::Stats.new.reset('retries')
# end

# def sidekiq_clear_stats_for_scheduled!
#   Sidekiq::Stats.new.reset('scheduled')
# end

# def sidekiq_clear_stats_for_dead!
#   Sidekiq.redis {|c| c.del('dead') }
# end

# ####
# # SPECIFIC SIDEKIQ JOBS
# # usage: Find jobs for class
# #    pp sidekiq_jobs [SetTextTagsWorker, BigqueryInitializeSyncWorker], :low
# #
# # usage: PURGE jobs for class
# #    pp sidekiq_jobs [SetTextTagsWorker, BigqueryInitializeSyncWorker], :low, purge: true
# #    pp sidekiq_jobs [ShoppingCartChangedWorker, ImpactOnChangeWorker,MemoizeStatsWorker], :critical, purge: true

# def sidekiq_jobs worker_klasses, queue_name="default", options={}
#   opts = options.with_indifferent_access
#   queue = Sidekiq::Queue.new(queue_name)
#   klasses = [*worker_klasses].flatten.compact.map &:name
#   queue.map do |job|
#     if klasses.include? job.klass
#       job.delete if opts[:purge]
#       puts "DELETING #{job.klass} #{job.args}" if opts[:purge]
#       {job_id: job.jid, job_klass: job.klass, arguments: job.args}
#     end
#   end.compact
# end

# def delete_jobs_by_id queue_name, ids
#   job_ids = [*ids].flatten.compact
#   queue = Sidekiq::Queue.new(queue_name)
#   job_ids.each do |jid|
#     job = queue.find_job(jid)
#     if job
#       puts "DELETING #{job.klass} #{job.args} from #{queue_name}"
#       job.delete 
#     end
#   end
# end

# # sidekiq_memoize_job_ids [MemoizeTouchWorker, MemoizeStatsWorker], ["Event", "Offer"], :critical
# def sidekiq_memoize_job_ids workers, models, queue_name="default"
#   opts = options.with_indifferent_access
#   queue = Sidekiq::Queue.new(queue_name)
#   worker_klasses = [*workers].flatten.compact.map &:name
#   model_classes = [*models].flatten.compact.map &:name
#   queue.map do |job|
#     if worker_klasses.include? job.klass and model_classes.include? job.args.first
#       job.jid
#     else
#       nil
#     end
#   end.compact
# end

# def sidekiq_idle?
#   busy_jobs_count = Sidekiq::Workers.new.count
#   enqueued_jobs_count = 0
#   SIDEKIQ_CONFIG[:queues].pluck(0).each { |q| enqueued_jobs_count += Sidekiq::Queue.new(q).count}
#   busy_jobs_count.zero? and enqueued_jobs_count.zero?
# end
