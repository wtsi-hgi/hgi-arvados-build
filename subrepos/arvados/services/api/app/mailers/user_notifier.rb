# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class UserNotifier < ActionMailer::Base
  include AbstractController::Callbacks

  default from: Rails.configuration.user_notifier_email_from

  def account_is_setup(user)
    @user = user
    mail(to: user.email, subject: 'Welcome to Curoverse - shell account enabled')
  end

end
