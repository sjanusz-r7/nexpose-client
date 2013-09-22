module Nexpose
  module NexposeAPI

    # List the scan templates currently configured on the console.
    #
    # @return [Array[String]] list of scan templates IDs.
    #
    def list_scan_templates
      templates = JSON.parse(AJAX.get(self, '/data/scan/templates'))
      templates['valueList']
    end

    alias_method :scan_templates, :list_scan_templates

    # Delete a scan template from the console.
    # Cannot be used to delete a built-in template.
    #
    # @param [String] id Unique identifier of an existing scan template.
    #
    def delete_scan_template(id)
      AJAX.delete(self, "/data/scan/templates/#{URI.encode(id)}")
    end
  end

  # Configuration object for a scan template.
  # This class is only a partial representation of some of the features
  # available for configuration.
  #
  class ScanTemplate

    # Whether to correlate reliable checks with regular checks.
    attr_accessor :correlate

    # Parsed XML of a scan template
    attr_reader :xml

    # @param [String] xml XML representation of a scan template.
    def initialize(xml)
      @xml = REXML::Document.new(xml)

      vuln_checks = REXML::XPath.first(@xml, 'ScanTemplate/VulnerabilityChecks')
      @correlate = vuln_checks.attributes['correlate'] == '1'
    end

    # @return [String] Unique identifier of the scan template.
    def id
      root = REXML::XPath.first(xml, 'ScanTemplate')
      root.attributes['id']
    end

    # @return [String] Name or title of this scan template.
    def name
      desc = REXML::XPath.first(@xml, 'ScanTemplate/templateDescription')
      desc.nil? ? nil : desc.attributes['title']
    end

    # Assign name to this scan template. Required attribute.
    # @param [String] name Title to assign.
    def name=(name)
      desc = REXML::XPath.first(@xml, 'ScanTemplate/templateDescription')
      if desc
        desc.attributes['title'] = name
      else
        root = REXML::XPath.first(xml, 'ScanTemplate')
        desc = REXML::Element.new('templateDescription')
        desc.add_attribute('title', name)
        root.add_element(desc)
      end
    end

    # @return [String] Description of this scan template.
    def description
      desc = REXML::XPath.first(@xml, 'ScanTemplate/templateDescription')
      desc.nil? ? nil : desc.text.to_s
    end

    # Assign a description to this scan template. Require attribute.
    # @param [String] description Description of the scan template.
    def description=(description)
      desc = REXML::XPath.first(@xml, 'ScanTemplate/templateDescription')
      if desc
        desc.text = description
      else
        root = REXML::XPath.first(xml, 'ScanTemplate')
        desc = REXML::Element.new('templateDescription')
        desc.add_text(description)
        root.add_element(desc)
      end
    end

    # Get a list of the check categories enabled for this scan template.
    #
    # @return [Array[String]] List of enabled categories.
    #
    def checks_by_category
      checks = REXML::XPath.first(@xml, '//VulnerabilityChecks/Enabled')
      checks.elements.to_a('VulnCategory').map { |c| c.attributes['name'] }
    end

    # Enable checks by category for this template.
    #
    # @param [String] category Category to enable. @see #list_vuln_categories
    #
    def enable_checks_by_category(category)
      _enable_check(category, 'VulnCategory')
    end

    # Disable checks by category for this template.
    #
    # @param [String] category Category to disable. @see #list_vuln_categories
    #
    def disable_checks_by_category(category)
      _disable_check(category, 'VulnCategory')
    end

    # Remove checks by category for this template. Removes both enabled and
    # disabled checks.
    #
    # @param [String] category Category to remove. @see #list_vuln_categories
    #
    def remove_checks_by_category(category)
      _remove_check(category, 'VulnCategory')
    end

    # Get a list of the check types enabled for this scan template.
    #
    # @return [Array[String]] List of enabled check types.
    #
    def checks_by_type
      checks = REXML::XPath.first(@xml, '//VulnerabilityChecks/Enabled')
      checks.elements.to_a('CheckType').map { |c| c.attributes['name'] }
    end

    # Enable checks by type for this template.
    #
    # @param [String] type Type to enable. @see #list_vuln_types
    #
    def enable_checks_by_type(type)
      _enable_check(type, 'CheckType')
    end

    # Disable checks by type for this template.
    #
    # @param [String] type Type to disable. @see #list_vuln_types
    #
    def disable_checks_by_type(type)
      _disable_check(type, 'CheckType')
    end

    # Remove checks by type for this template. Removes both enabled and
    # disabled checks.
    #
    # @param [String] type Type to remove. @see #list_vuln_types
    #
    def remove_checks_by_type(type)
      _remove_check(type, 'CheckType')
    end

    def _enable_check(check, elem)
      checks = REXML::XPath.first(@xml, '//VulnerabilityChecks')
      checks.elements.delete("Disabled/#{elem}[@name='#{check}']")
      checks.elements['Enabled'].add_element(elem, { 'name' => check })
    end

    def _disable_check(check, elem)
      checks = REXML::XPath.first(@xml, '//VulnerabilityChecks')
      checks.elements.delete("Enabled/#{elem}[@name='#{check}']")
      checks.elements['Disabled'].add_element(elem, { 'name' => check })
    end

    def _remove_check(check, elem)
      checks = REXML::XPath.first(@xml, '//VulnerabilityChecks')
      checks.elements.delete("Disabled/#{elem}[@name='#{check}']")
      checks.elements.delete("Enabled/#{elem}[@name='#{check}']")
    end

    # Save this scan template configuration to a Nexpose console.
    #
    # @param [Connection] nsc API connection to a Nexpose console.
    #
    def save(nsc)
      root = REXML::XPath.first(@xml, 'ScanTemplate')

      vuln_checks = REXML::XPath.first(root, 'VulnerabilityChecks')
      vuln_checks.attributes['correlate'] = (@correlate ? '1' : '0')

      if root.attributes['id'] == '#NewScanTemplate#'
        response = JSON.parse(AJAX.post(nsc, '/data/scan/templates', xml))
      else
        response = JSON.parse(AJAX.put(nsc, "/data/scan/templates/#{URI.encode(id)}", xml))
      end
      response['value']
    end

    # Load a scan template.
    #
    # @param [Connection] nsc API connection to a Nexpose console.
    # @param [String] id Unique identifier of an existing scan template.
    #   If no ID is provided, a blank, base template will be returned.
    # @return [ScanTemplate] The requested scan template configuration.
    #
    def self.load(nsc, id = nil)
      if id
        response = JSON.parse(AJAX.get(nsc, "/data/scan/templates/#{URI.encode(id)}"))
        xml = response['value']
      else
        xml = AJAX.get(nsc, '/ajax/scantemplate_config.txml')
      end
      new(xml)
    end

    # Copy an existing scan template, changing the id and title.
    #
    # @param [Connection] nsc API connection to a Nexpose console.
    # @param [String] id Unique identifier of an existing scan template.
    # @return [ScanTemplate] A copy of the requested scan template configuration.
    #
    def self.copy(nsc, id)
      dupe = load(nsc, id)
      dupe.id = '#NewScanTemplate#'
      dupe.title = "#{dupe.title} Copy"
      dupe
    end

    # Delete this scan template from the console.
    # Cannot be used to delete a built-in template.
    #
    # @param [Connection] nsc API connection to a Nexpose console.
    #
    def delete(nsc)
      nsc.delete_scan_template(@id)
    end
  end
end
