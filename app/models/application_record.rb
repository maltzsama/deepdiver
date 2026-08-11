# Base class for all application models; sets up Active Record's primary
# abstract class so shared configuration and schema live in a single root.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
