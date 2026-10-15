# Optional Actools BS5 theme on a BOA Composer platform

## Status and boundary

The operator tested this custom standalone theme on Drupal 11.4.10 / PHP 8.4.26
on 15–16 October 2026. All six Layout Builder section choices appeared. The
50/50 layout rendered on desktop, stacked on a narrow screen without horizontal
scrolling, and survived reloads. An author-heading correction was then applied
and confirmed visually. These are limited operator/browser observations, not
full Drupal Kernel/Functional test results or production certification.

This is an optional site/platform addition, not a BOA installation dependency.
Build the theme into a new platform before registration. It does not require
Varbase, Canvas, CVA, Barrio, Node or Sass at runtime. The declared core
constraint is ^11.3, excluding Drupal 12. The version string 5.0.0-beta1 is
inherited from the supplied Vartheme-derived custom fork; it is not an upstream
stable release or a security-support guarantee.

The theme archive is supplied separately by the operator, not downloaded by
this installer or vendored into this repository. Its original Vardot attribution
and GPL-2.0-or-later licence must be retained. Keep a reviewed archive/source
copy with your platform backups.

## Reviewed archive

The corrected package, including the recorded browser result, is named:

~~~text
actools_bs5-standalone-fixed-2026-10-16.zip
SHA256 395b1993eb630867bb813ce58b2d375df5550d2d310c846eadb50d69c5518d50
~~~

This checksum identifies that exact artifact, not future builds under a similar
name. No public theme-release URL or automatic theme-update service is configured.
Obtain the reviewed archive from the operator and verify its checksum before
extracting/uploading it. The earlier 15 October package needs the metadata and
user-template corrections described below.

## 1. Assemble an unregistered platform

Use the real o1.ftp limited shell for Composer. From root, enter it with:

~~~bash
su - o1.ftp
~~~

Run the following commands **individually**, stopping after any failure.
The limited shell rejects && chaining, and direct php was forbidden on the
reference. Copy commands only, not terminal prompts or earlier output. If the
limited shell terminates, subsequent pasted commands would run at the root
prompt: cancel any root Composer prompt with Ctrl+C and re-enter o1.ftp.

The versions below reproduce the dated test. Select a currently supported core
release for a new deployment and audit the actual lock file.

~~~bash
cd ~/static/platforms
composer create-project --no-dev --no-interaction drupal/recommended-project:11.4.10 site-d11-theme-01
cd site-d11-theme-01
composer require --no-interaction --update-no-dev drupal/smtp:1.4.0 drush/drush:13.8.0
composer validate --no-check-publish
composer check-platform-reqs --no-dev
composer audit --no-dev
mkdir -p web/themes/custom
~~~

The SMTP dependency preserves the module used by the reference site. Include
all other modules/themes used by any site that will be migrated. Exact-version
constraint warnings in validation were expected; security advisories or failed
platform requirements are not acceptable build results.

Extract the archive locally and upload its actools_bs5 directory to:

~~~text
/data/disk/o1/static/platforms/site-d11-theme-01/web/themes/custom/actools_bs5
~~~

The info file must be directly inside that directory, not under another nested
actools_bs5 folder. SFTP as o1.ftp is convenient. If the existing Bitvise SFTP
connection is root, upload only to this new platform; then, as root, give only
the uploaded theme directory to the build account:

~~~bash
chown -R o1.ftp:o1 /data/disk/o1/static/platforms/site-d11-theme-01/web/themes/custom/actools_bs5
~~~

Do not change ownership of the whole static tree or weaken the limited shell.

From the **root** shell, check the two runtime PHP files using the installed
PHP binary. This is syntax lint, not a Drupal installation/rendering test:

~~~bash
/opt/php84/bin/php -l /data/disk/o1/static/platforms/site-d11-theme-01/web/themes/custom/actools_bs5/actools_bs5.theme
/opt/php84/bin/php -l /data/disk/o1/static/platforms/site-d11-theme-01/web/themes/custom/actools_bs5/theme-settings.php
~~~

Use the compiled CSS already in the package. Its slim Sass build does not yet
reproduce all shipped selectors. Node build/check/publish tooling is for a
separate development environment; do not rebuild CSS on the registered platform.

## 2. Register and move a test site

In Aegir, choose Platforms > Add platform. Give it a distinct name and use the
full Publish Path:

~~~text
/data/disk/o1/static/platforms/site-d11-theme-01/web
~~~

Leave deployment from a makefile empty. Save and wait for Verify/Lock Drush to
turn green. Finish Composer work before this point. Use a new platform for
later dependency/code releases rather than Composer updates inside a live one.

For production, rehearse on a clone. For a disposable acceptance site, first
create a fresh **Site files with classic mysqldump DB** backup and wait for green;
confirm no pending database updates, then Migrate to the new platform. Keep the
domain and database server unchanged. Check content, uploaded images and login.

The theme session reported platform Verify green and subsequently showed site
content under the theme. A separate explicit report of the requested pre-theme
backup and migration tasks turning green was not collected; screenshots alone
do not prove those task results.

Aegir site Backup excludes shared platform code. Back up the complete custom
code, Composer manifest/lock and needed build files separately from the site
archive; site SMTP settings/backups may contain credentials.

## 3. Enable and configure the theme

In Drupal Appearance, install Actools BS5 and set it as default. Retain Claro as
the administration theme. Then check:

- Theme settings > Containers: use Container for Header, Content and Footer
  for a conventional aligned starting layout.
- Block layout > Actools BS5 > Site branding: disable Site logo and enable
  Site name, or upload your own logo through the theme settings. The supplied
  artwork was inherited Varbase branding; renaming a theme does not redraw it.
- Basic site settings: set the desired default front page. The reference used
  /node/1; an empty default content listing does not indicate lost node content.

These settings belong to the site database and are not included in theme code.

The corrected info file omits project and the inherited packaging datestamp.
The old project: actools_bs5 line caused Drupal's Available updates report to
look for a Drupal.org release feed that this custom package does not supply.
After correction, clear all Drupal caches and check updates again. Core and
contributed-project update monitoring must stay enabled. Track this theme's
updates/security reviews separately; an absent warning is not a security audit.

## 4. Exercise Layout Builder

Enable the core Layout Builder and Layout Discovery modules in Extend.
Create a separate Theme Test content type.

**Drupal 11.1+ does not automatically add Body to a new content type.** On
Manage fields, check first; if absent, create an appropriate Text (formatted,
long) field labelled Body. Do not create a duplicate if one already exists.

On the type's Manage display page, open the **Default** view mode from the
Overview page. Enable Use Layout Builder, save, then Manage layout > Add section.
The Actools sections category should offer:

| Layout | Desktop regions |
| --- | --- |
| One column (contained) | One contained region |
| One column (full available width) | One region filling its parent |
| Two columns (50/50) | Two equal regions |
| Two columns (33/67) | Narrow then wide |
| Two columns (67/33) | Wide then narrow |
| Three columns (equal) | Three equal regions |

For the recorded smoke test, put Body in the left side of a 50/50 section and
System > Powered by Drupal in the right. Remove a redundant original section
so fields are not rendered twice, then save the layout. Create/publish a test
node of this type and check desktop, narrow width below 768px, and reloads.

Full available width respects the surrounding content container. For sections
that need the full viewport, set the theme's Content container to No Container
and use contained sections for narrower content.

## 5. Compact author correction

Core renders a node's author picture using the compact user view mode. The
supplied wrapper always added the user's profile heading, producing a large
duplicate admin heading above the submission line. This corrected wrapper reads
the actual render-array mode, keeps picture/content, and omits profile headings
and action links in compact mode:

~~~twig
{% set user_view_mode = elements['#view_mode']|default(view_mode|default('full')) %}
{% set is_compact = user_view_mode == 'compact' %}
{% include 'actools_bs5:user' with {
  user_label: is_compact ? '' : user.getDisplayName(),
  user_actions: is_compact ? [] : user_actions|default([]),
  view_mode: user_view_mode,
} %}
~~~

It belongs at templates/user/user.html.twig inside the theme. For an existing
test platform, take a root-private backup of that file before a targeted repair.
Clear Drupal caches, then confirm the extra heading is absent while the
submission line and layout remain. This passed on the reference node page.
Normal account/profile pages and actual avatar images still need acceptance.

## Remaining checks and fork integration

Only layout discovery and the 50/50 rendering/responsive/reload case have been
confirmed. Test the other five layouts, editing/reordering, keyboard use,
menus/forms/account pages, token/font settings, actual author images, print and
the supplied Kernel/Functional suites in a suitable disposable test environment.
The new compact/full regression was added to the package but has not run here.

This guide is the optional integration in the BOA fork. Before adding automated
theme retrieval, publish/maintain a separate versioned theme source or release,
pin a reviewed version and checksum, and define an update path. Do not silently
enable the theme, Layout Builder or a sample content type for all BOA sites.

References:

- [BOA custom-platform workflow](https://docs.boa.io/using/deploying-code/building-a-platform)
- [Drupal Layout Builder defaults](https://www.drupal.org/docs/8/core/modules/layout-builder/creating-layout-defaults)
- [Drupal 11.1 Body-field change](https://www.drupal.org/node/3489270)
- [Custom-theme release metadata](https://www.drupal.org/docs/develop/theming-drupal/creating-sub-themes#s-avoid-no-available-releases-found)
