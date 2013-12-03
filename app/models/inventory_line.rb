# = Informations
# 
# == License
# 
# Ekylibre - Simple ERP
# Copyright (C) 2009-2010 Brice Texier, Thibaud Mérigon
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
# == Table: inventory_lines
#
#  company_id       :integer          not null
#  created_at       :datetime         not null
#  creator_id       :integer          
#  id               :integer          not null, primary key
#  inventory_id     :integer          not null
#  location_id      :integer          not null
#  lock_version     :integer          default(0), not null
#  product_id       :integer          not null
#  quantity         :decimal(16, 4)   not null
#  theoric_quantity :decimal(16, 4)   not null
#  tracking_id      :integer          
#  unit_id          :integer          
#  updated_at       :datetime         not null
#  updater_id       :integer          
#

class InventoryLine < ActiveRecord::Base

  belongs_to :company
  belongs_to :inventory
  belongs_to :location
  belongs_to :product
  belongs_to :tracking
  belongs_to :unit
  has_many :stock_moves, :as=>:origin, :dependent=>:destroy

  attr_readonly :company_id

  def before_validation
    self.company_id = self.inventory.company_id if self.inventory
  end

  def stock_id=(id)
    if s = Stock.find_by_id_and_company_id(id, self.company_id)
      self.product_id  = s.product_id
      self.location_id = s.location_id
      self.tracking_id = s.tracking_id
      self.theoric_quantity = s.quantity||0
      self.unit_id     = s.unit_id
    end
  end

  # def after_save
  #   if self.inventory.changes_reflected
  #     self.reflect_changes
  #   end
  # end

  def tracking_name
    return self.tracking ? self.tracking.name : ""
  end
  
end