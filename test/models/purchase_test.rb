# = Informations
#
# == License
#
# Ekylibre - Simple ERP
# Copyright (C) 2009-2013 Brice Texier, Thibaud Merigon
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
# == Table: purchases
#
#  accounted_at        :datetime
#  affair_id           :integer
#  amount              :decimal(19, 4)   default(0.0), not null
#  confirmed_on        :date
#  created_at          :datetime         not null
#  created_on          :date
#  creator_id          :integer
#  currency            :string(3)        not null
#  delivery_address_id :integer
#  description         :text
#  id                  :integer          not null, primary key
#  invoiced_on         :date
#  journal_entry_id    :integer
#  lock_version        :integer          default(0), not null
#  nature_id           :integer
#  number              :string(60)       not null
#  planned_on          :date
#  pretax_amount       :decimal(19, 4)   default(0.0), not null
#  reference_number    :string(255)
#  responsible_id      :integer
#  state               :string(60)
#  supplier_id         :integer          not null
#  updated_at          :datetime         not null
#  updater_id          :integer
#


require 'test_helper'

class PurchaseTest < ActiveSupport::TestCase

end