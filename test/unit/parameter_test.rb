# = Informations
# 
# == License
# 
# Ekylibre - Simple ERP
# Copyright (C) 2009-2013 Brice Texier, Thibaud Mérigon
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
# 
# == Table: parameters
#
#  boolean_value     :boolean          
#  company_id        :integer          not null
#  created_at        :datetime         not null
#  creator_id        :integer          
#  decimal_value     :decimal(16, 4)   
#  id                :integer          not null, primary key
#  integer_value     :integer          
#  lock_version      :integer          default(0), not null
#  name              :string(255)      not null
#  nature            :string(8)        default("u"), not null
#  record_value_id   :integer          
#  record_value_type :string(255)      
#  string_value      :text             
#  updated_at        :datetime         not null
#  updater_id        :integer          
#  user_id           :integer          
#

require 'test_helper'

class ParameterTest < ActiveSupport::TestCase
  # Replace this with your real tests.
  def test_truth
    assert true
  end
end