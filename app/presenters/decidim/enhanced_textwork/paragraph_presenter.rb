# frozen_string_literal: true

module Decidim
  module EnhancedTextwork
    #
    # Decorator for paragraphs
    #
    class ParagraphPresenter < Decidim::ResourcePresenter
      include Rails.application.routes.mounted_helpers
      include ActionView::Helpers::UrlHelper

      def author
        @author ||= if official?
                      Decidim::EnhancedTextwork::OfficialAuthorPresenter.new
                    else
                      coauthorship = coauthorships.includes(:author, :user_group).first
                      coauthorship.user_group&.presenter || coauthorship.author.presenter
                    end
      end

      def paragraph
        __getobj__
      end

      def paragraph_path
        Decidim::ResourceLocatorPresenter.new(paragraph).path
      end

      def display_mention
        link_to title, paragraph_path
      end

      # Render the paragraph title
      #
      # links - should render hashtags as links?
      # extras - should include extra hashtags?
      #
      # Returns a String.
      def title(links: false, extras: true, html_escape: false, all_locales: false)
        return unless paragraph

        super paragraph.title, links, html_escape, all_locales, extras: extras
      end

      # Render the paragraph title if it is not numeric and if showing it is enabled
      #
      # links - should render hashtags as links?
      # extras - should include extra hashtags?
      #
      # Returns a String.
      def title_if_enabled
        return unless paragraph
        return "" if paragraph.component.settings.hide_participatory_text_titles_enabled? && translated_attribute(paragraph.title) !~ /\D/

        translated_attribute(paragraph.title)
      end

      def id_and_title(links: false, extras: true, html_escape: false)
        "##{paragraph.id} - #{title(links: links, extras: extras, html_escape: html_escape)}"
      end

      def body(links: false, extras: true, strip_tags: false, all_locales: false)
        return unless paragraph

        handle_locales(paragraph.body, all_locales) do |content|
          content = strip_tags(sanitize_text(content)) if strip_tags

          renderer = Decidim::ContentRenderers::HashtagRenderer.new(content)
          content = renderer.render(links: links, extras: extras).html_safe

          content = Decidim::ContentRenderers::LinkRenderer.new(content).render if links
          content
        end
      end

      # Returns the paragraph versions, hiding not published answers
      #
      # Returns an Array.
      def versions
        version_state_published = false
        pending_state_change = nil

        paragraph.versions.map do |version|
          state_published_change = version.changeset["state_published_at"]
          version_state_published = state_published_change.last.present? if state_published_change

          if version_state_published
            version.changeset["state"] = pending_state_change if pending_state_change
            pending_state_change = nil
          elsif version.changeset["state"]
            pending_state_change = version.changeset.delete("state")
          end

          next if version.event == "update" && Decidim::EnhancedTextwork::DiffRenderer.new(version).diff.empty?

          version
        end.compact
      end

      delegate :count, to: :versions, prefix: true

      def resource_manifest
        paragraph.class.resource_manifest
      end

      private

      def sanitize_unordered_lists(text)
        text.gsub(%r{(?=.*</ul>)(?!.*?<li>.*?</ol>.*?</ul>)<li>}) { |li| "#{li}• " }
      end

      def sanitize_ordered_lists(text)
        i = 0

        text.gsub(%r{(?=.*</ol>)(?!.*?<li>.*?</ul>.*?</ol>)<li>}) do |li|
          i += 1

          li + "#{i}. "
        end
      end

      def add_line_feeds_to_paragraphs(text)
        text.gsub("</p>") { |p| "#{p}\n\n" }
      end

      def add_line_feeds_to_list_items(text)
        text.gsub("</li>") { |li| "#{li}\n" }
      end

      # Adds line feeds after the paragraph and list item closing tags.
      #
      # Returns a String.
      def add_line_feeds(text)
        add_line_feeds_to_paragraphs(add_line_feeds_to_list_items(text))
      end

      # Maintains the paragraphs and lists separations with their bullet points and
      # list numberings where appropriate.
      #
      # Returns a String.
      def sanitize_text(text)
        add_line_feeds(sanitize_ordered_lists(sanitize_unordered_lists(text)))
      end
    end
  end
end
