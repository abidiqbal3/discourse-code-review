# frozen_string_literal: true

module DiscourseCodeReview
    class Hooks
      class << self
        def add_parent_category_finder(key, &blk)
          @finders ||= {}
          @finders[key] = blk
        end
  
        def remove_parent_category_finder(key)
          @finders.delete(key)
          @finders = nil if @finders.length == 0
        end
  
        def apply_parent_category_finder(repo_name, repo_id, issues)
          parent_category_id = nil
          if @finders
            @finders.each do |key, finder|
              parent_category_id = finder.call(repo_name, repo_id, issues)
              break if parent_category_id.present?
            end
          end
          parent_category_id
        end
  
        def add_category_namer(key, &blk)
          @namers ||= {}
          @namers[key] = blk
        end
  
        def remove_category_namer(key)
          @namers.delete(key)
          @namers = nil if @namers.length == 0
        end
  
        def apply_category_namer(repo_name, repo_id, issues)
          name = nil
          if @namers
            @namers.each do |key, namer|
              name = namer.call(repo_name, repo_id, issues)
              break if name.present?
            end
          end
        end
      end
    end
  end