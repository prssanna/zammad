# encoding: utf-8
require 'browser_test_helper'

class MaintenanceAppVersionTest < TestCase
  def test_app_version
    @browser = browser_instance
    login(
      username: 'master@example.com',
      password: 'test',
      url: browser_url,
    )

    sleep 10

    execute(
      js: 'App.Event.trigger("app_version", {app_version:"1234:false"})',
    )
    sleep 10

    match_not(
      css: 'body',
      value: 'new version',
    )

    execute(
      js: 'App.Event.trigger("app_version", {app_version:"1235:true"})',
    )
    sleep 5

    match(
      css: 'body',
      value: 'new version',
    )

  end
end
